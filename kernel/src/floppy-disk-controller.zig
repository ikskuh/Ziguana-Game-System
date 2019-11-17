const IO = @import("io.zig");
const TextTerminal = @import("text-terminal.zig");
const std = @import("std");

const CMOS = @import("cmos.zig");
const ISA_DMA = @import("isa-dma.zig");
const Interrupts = @import("interrupts.zig");
const Timer = @import("timer.zig");

const BlockIterator = @import("block-iterator.zig").BlockIterator;

const use_dma = true;

const FloppyID = enum(u2) {
    A = 0,
    B = 1,
    C = 2,
    D = 3,
};

const Error = error{
    DriveNotAvailable,
    NoDriveSelected,
    GenericFailure,
    Timeout,
    UnalignedBufferSize,
    InvalidBufferSize,
};

const MotorState = enum {
    on,
    off,
};

const Drive = struct {
    id: u2,
    available: bool,
    current_status: u8,
    current_cylinder: u8,
    motor: MotorState = .off,
};

var floppyDrives: [4]Drive = [_]Drive{Drive{
    .id = undefined,
    .available = false,
    .current_status = undefined,
    .current_cylinder = undefined,
}} ** 4;

var currentDrive: ?*Drive = null;

fn getCurrentDrive() Error!*Drive {
    if (currentDrive) |drive| {
        return drive;
    } else {
        return error.NoDriveSelected;
    }
}

const CHS = struct {
    cylinder: u8,
    head: u8,
    sector: u8,
};

// Eine LBA in eine Adresse als CHS umwandeln
fn lba2chs(lba: u32) CHS {
    return CHS{
        .sector = @intCast(u8, (lba % FLOPPY_SECTORS_PER_TRACK) + 1),
        .cylinder = @intCast(u8, (lba / FLOPPY_SECTORS_PER_TRACK) / FLOPPY_HEAD_COUNT),
        .head = @intCast(u8, (lba / FLOPPY_SECTORS_PER_TRACK) % FLOPPY_HEAD_COUNT),
    };
}

pub fn init() !void {
    const disks = CMOS.getFloppyDrives();

    for (floppyDrives) |*drive, i| {
        drive.id = @intCast(u2, i);
        drive.available = switch (i) {
            0 => if (disks.A) |t| t == .microHD else false,
            1 => if (disks.B) |t| t == .microHD else false,
            else => false,
        };
    }

    Interrupts.setIRQHandler(6, handleIRQ);
    Interrupts.enableIRQ(6);

    try floppy_reset_controller();

    for (floppyDrives) |drive| {
        if (!drive.available)
            continue;

        try floppy_drive_select(@intToEnum(FloppyID, drive.id));

        try floppy_drive_set_dataRate();

        try floppy_drive_int_sense();
        try floppy_drive_specify();
        try floppy_drive_recalibrate();
    }
}

var irq_count: u32 = 0;

fn handleIRQ(cpu: *Interrupts.CpuState) *Interrupts.CpuState {
    var cnt = @atomicRmw(u32, &irq_count, .Add, 1, .SeqCst);
    return cpu;
}

fn floppy_reset_irqcnt() void {
    _ = @atomicRmw(u32, &irq_count, .Xchg, 0, .Release);
}

fn floppy_wait_irq(timeout: u32) Error!void {
    // TODO: Timeout
    while (@atomicLoad(u32, &irq_count, .Acquire) == 0) {
        asm volatile ("hlt");
    }
}

fn floppy_reset_controller() Error!void {
    var dor = floppy_read_byte(FLOPPY_REG_DOR);

    floppy_reset_irqcnt();

    // No-Reset Bit loeschen
    dor &= ~FLOPPY_DOR_NRST;
    floppy_write_byte(FLOPPY_REG_DOR, dor);

    // Wir wollen Interrupts bei Datentransfers
    dor |= FLOPPY_DOR_DMAGATE;

    // No-Reset Bit wieder setzen
    dor |= FLOPPY_DOR_NRST;
    floppy_write_byte(FLOPPY_REG_DOR, dor);

    try floppy_wait_irq(FLOPPY_RESET_TIMEOUT);
}

pub fn selectDrive(id: FloppyID) Error!void {
    try floppy_drive_select(id);
}

fn floppy_drive_select(id: FloppyID) Error!void {
    const drive = &floppyDrives[@enumToInt(id)];
    if (!drive.available)
        return error.DriveNotAvailable;

    var dor = floppy_read_byte(FLOPPY_REG_DOR);

    dor &= ~FLOPPY_DOR_DRIVE_MASK;
    dor |= @enumToInt(id);

    floppy_write_byte(FLOPPY_REG_DOR, dor);

    currentDrive = drive;
}

fn floppy_drive_set_dataRate() Error!void {
    // TODO: Wie kriegen wir hier das Optimum raus?
    // Mit 500Kb/s sind wir auf der sicheren Seite
    const dsr = FLOPPY_DSR_500KBPS;
    floppy_write_byte(FLOPPY_REG_DSR, dsr);
}

fn floppy_drive_int_sense() Error!void {
    var drive = try getCurrentDrive();

    // Befehl senden
    // Byte 0:  FLOPPY_CMD_INT_SENSE
    try floppy_write_data(FLOPPY_CMD_INT_SENSE);

    // Ergebnis abholen
    // Byte 0:  Status 0
    // Byte 1:  Zylinder auf dem sich der Kopf gerade befindet
    drive.current_status = try floppy_read_data();
    drive.current_cylinder = try floppy_read_data();
}

// Specify
// Diese Funktion konfiguriert den Kontroller im Bezug auf verschiedene delays.
// Ist im allgemeinen sehr schlecht dokumentiert. Die Erklaerungen basieren
// groesstenteils auf http://www.osdev.org/wiki/Floppy_Disk_Controller
fn floppy_drive_specify() Error!void {
    // Die head unload time legt fest, wie lange der Kontroller nach einem
    // Lese- oder Schreibvorgang warten soll, bis der den Kopf wieder in den
    // "entladenen" Status gebracht wird. Vermutlich wird diese Aktion nicht
    // ausgefuehrt, wenn dazwischen schon wieder ein Lesevorgang eintrifft,
    // aber das ist nicht sicher. Dieser Wert ist abhaengig von der Datenrate.
    // Laut dem OSdev-Wiki kann hier fuer die bestimmung des optimalen Wertes
    // die folgende Berechnung benutzt werden:
    //      head_unload_time = seconds * data_rate / 8000
    // Als vernuenftiger Wert fuer die Zeit, die gewartet werden soll, wird
    // dort 240ms vorgeschlagen. Wir uebernehmen das hier mal so.
    const head_unload_time: u8 = 240 * FLOPPY_DATA_RATE / 8000 / 1000;

    // Die head load time ist die Zeit, die der Kontroller warten soll, nachdem
    // er den Kopf zum Lesen oder Schreiben positioniert hat, bis der Kopf
    // bereit ist. Auch dieser Wert haengt wieder von der Datenrate ab.
    // Der optimale Wert kann nach OSdev-Wiki folgendermassen errechnet werden:
    //      head_load_time = seconds * data_rate / 1000
    // Die vorgeschlagene Zeit liegt bei 10 Millisekunden.
    const head_load_time: u8 = 20 * FLOPPY_DATA_RATE / 1000 / 1000;

    // Mit der step rate time wird die Zeit bestimmt, die der Kontroller warten
    // soll, wenn der den Kopf zwischen den einzelnen Spuren bewegt. Wozu das
    // genau dient konnte ich bisher nirgends finden.
    // Der hier einzustellende Wert ist genau wie die vorderen 2 abhaengig von
    // der Datenrate.
    // Aus dem OSdev-Wiki stammt die folgende Formel fuer die Berechnung:
    //      SRT_value = 16 - (milliseconds * data_rate / 500000)
    // Fuer die Zeit wird 8ms empfohlen.
    const step_rate_time: u8 = 16 - 8 * FLOPPY_DATA_RATE / 500 / 1000;

    // Befehl und Argumente Senden
    // Byte 0:  FLOPPY_CMD_SPECIFY
    // Byte 1:  Bits 0 - 3: Head unload time
    //          Bits 4 - 7: Step rate time
    // Byte 2:  Bit 0: No DMA; Deaktiviert DMA fuer dieses Geraet
    //          Bit 1 - 7: Head load time
    try floppy_write_data(FLOPPY_CMD_SPECIFY);
    try floppy_write_data((head_unload_time & 0xF) | (step_rate_time << 4));
    if (use_dma) {
        try floppy_write_data((head_load_time << 1));
    } else {
        try floppy_write_data((head_load_time << 1) | 1);
    }

    // Rueckgabewerte gibt es keine
}

// Neu kalibrieren
// Diese Funktion hilft vorallem dabei, Fehler die beim Seek, Read oder auch
// write auftreten auftreten zu beheben.
fn floppy_drive_recalibrate() Error!void {
    var drive = try getCurrentDrive();
    // Wenn das neu kalibrieren fehlschlaegt, wird mehrmals probiert.

    var i: usize = 0;
    while (i < FLOPPY_RECAL_TRIES) : (i += 1) {
        floppy_reset_irqcnt();

        // Befehl und Attribut senden
        // Byte 0:  FLOPPY_CMD_RECALIBRATE
        // Byte 1:  Bit 0 und 1: Geraetenummer
        try floppy_write_data(FLOPPY_CMD_RECALIBRATE);
        try floppy_write_data(drive.id);

        // Auf den IRQ warten, wenn der nicht kommt, innerhalb der angebenen
        // Frist, stimmt vermutlich etwas nicht.
        floppy_wait_irq(FLOPPY_RECAL_TIMEOUT) catch |err| {
            if (err == error.Timeout)
                continue;
            return err;
        };

        // Rueckgabewerte existieren nicht.

        // Aktualisiert current_cylinder damit geprueft werden kann, ob
        // erfolgreich neu kalibriert wurde und signalisiert dem FDC, dass der
        // IRQ behandelt wurde.
        try floppy_drive_int_sense();

        // Nach erfolgreichem neukalibrieren steht der Kopf ueber dem
        // Zylinder 0.
        if (drive.current_cylinder == 0) {
            return;
        }
    }

    return error.GenericFailure;
}

comptime {
    _ = selectDrive;
    _ = readBlocks;
    _ = writeBlocks;
}

const IsaOrFdcError = ISA_DMA.Error || Error;

// Sektoren einlesen
pub fn readBlocks(firstBlock: usize, buffer: []u8) IsaOrFdcError!void {
    if (!std.mem.isAligned(buffer.len, FLOPPY_SECTOR_SIZE))
        return error.UnalignedBufferSize;

    const blockCount = buffer.len / FLOPPY_SECTOR_SIZE;

    TextTerminal.println("block count: {}", blockCount);

    var iter = BlockIterator(@import("block-iterator.zig").IteratorKind.mutable).init(firstBlock, buffer, FLOPPY_SECTOR_SIZE) catch unreachable; // we check already if block size is aligned

    while (iter.next()) |block| {
        var i: usize = 0;
        var lastErr: IsaOrFdcError = undefined;
        while (i < 5) : (i += 1) {
            floppy_drive_sector_read(block.block, block.slice) catch |err| {
                lastErr = err;
                continue;
            };
            break;
        }
        TextTerminal.println("read {} after {} tries", block.block, i);
        if (i >= 5)
            return lastErr;
    }
    TextTerminal.println("done.");
}

// Sektoren schreiben
pub fn writeBlocks(block: usize, buffer: []const u8) IsaOrFdcError!void {
    if (!std.mem.isAligned(buffer.len, FLOPPY_SECTOR_SIZE))
        return error.UnalignedBufferSize;

    const blockCount = buffer.len / FLOPPY_SECTOR_SIZE;

    var offset: usize = 0;
    while (offset < blockCount) : (offset += 1) {
        var i: usize = 0;
        var lastErr: IsaOrFdcError = undefined;
        while (i < 5) : (i += 1) {
            floppy_drive_sector_write(block + offset, buffer[offset * FLOPPY_SECTOR_SIZE .. (offset + 1) * FLOPPY_SECTOR_SIZE]) catch |err| {
                lastErr = err;
                continue;
            };
            break;
        }
        if (i >= 5)
            return lastErr;
    }
}

// Sektor einlesen
fn floppy_drive_sector_read(lba: u32, buffer: []u8) IsaOrFdcError!void {
    const drive = try getCurrentDrive();

    if (buffer.len != FLOPPY_SECTOR_SIZE)
        return error.InvalidBufferSize;

    // Adresse in CHS umwandeln weil READ nur CHS als Parameter nimmt
    const chs = lba2chs(lba);

    // Und bevor irgendetwas gemacht werden kann, stellen wir sicher, dass der
    // Motor laeuft.
    try floppy_drive_motor_set(.on);

    // Kopf richtig positionieren
    floppy_drive_seek(chs.cylinder, chs.head) catch |err| {
        // Neu kalibrieren und nochmal probiren
        try floppy_drive_recalibrate();
        try floppy_drive_seek(chs.cylinder, chs.head);
    };

    // Wenn DMA aktiviert ist, wird es jetzt initialisiert
    var dma_handle = if (use_dma) try ISA_DMA.beginRead(FLOPPY_DMA_CHANNEL, buffer, .single) else {};
    defer if (use_dma) {
        dma_handle.close();
    };

    try floppy_drive_int_sense();

    floppy_reset_irqcnt();

    // Befehl und Argumente senden
    // Byte 0: FLOPPY_CMD_READ
    // Byte 1: Bit 2:       Kopf (0 oder 1)
    //         Bits 0/1:    Laufwerk
    // Byte 2: Zylinder
    // Byte 3: Kopf
    // Byte 4: Sektornummer (bei Multisektortransfers des ersten Sektors)
    // Byte 5: Sektorgroesse (Nicht in bytes, sondern logarithmisch mit 0 fuer
    //                      128, 1 fuer 256 usw.)
    // Byte 6: Letzte Sektornummer in der aktuellen Spur
    // Byte 7: Gap Length
    // Byte 8: DTL (ignoriert, wenn Sektorgroesse != 0. 0xFF empfohlen)
    try floppy_write_data(FLOPPY_CMD_READ);
    try floppy_write_data((chs.head << 2) | drive.id);
    try floppy_write_data(chs.cylinder);
    try floppy_write_data(chs.head);
    try floppy_write_data(chs.sector);
    try floppy_write_data(FLOPPY_SECTOR_SIZE_CODE);
    try floppy_write_data(FLOPPY_SECTORS_PER_TRACK);
    try floppy_write_data(FLOPPY_GAP_LENGTH);
    try floppy_write_data(0xFF);

    if (!use_dma) {
        TextTerminal.println("PIOread");

        // Bei PIO kommt nach jedem gelesenen Byte ein Interrupt
        for (buffer) |*byte, i| {
            try floppy_wait_irq(FLOPPY_READ_TIMEOUT);

            // IRQ bestaetigen
            try floppy_drive_int_sense();
            floppy_reset_irqcnt();
            byte.* = try floppy_read_data();
        }
    }

    // Sobald der Vorgang beendet ist, kommt wieder ein IRQ
    try floppy_wait_irq(FLOPPY_READ_TIMEOUT);

    // Die Rueckgabewerte kommen folgendermassen an:
    // Byte 0: Status 0
    // Byte 1: Status 1
    // Byte 2: Status 2
    // Byte 3: Zylinder
    // Byte 4: Kopf
    // Byte 5: Sektornummer
    // Byte 6: Sektorgroesse (siehe oben)
    const status = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();

    // Pruefen ob der Status in Ordnung ist
    if ((status & FLOPPY_ST0_IC_MASK) != FLOPPY_ST0_IC_NORMAL) {
        return error.GenericFailure;
    }

    // Reading is done because DMA has already filled the buffer :)
}

// Sektor schreiben
fn floppy_drive_sector_write(lba: u32, buffer: []const u8) IsaOrFdcError!void {
    if (buffer.len != FLOPPY_SECTOR_SIZE)
        return error.InvalidBufferSize;

    var drive = try getCurrentDrive();

    // Adresse in CHS-Format umwandeln, weil die Funktionen nur das als
    // Parameter nehmen.
    const chs = lba2chs(lba);

    // Und bevor irgendetwas gemacht werden kann, stellen wir sicher, dass der
    // Motor laeuft.
    try floppy_drive_motor_set(.on);

    // Kopf richtig positionieren
    floppy_drive_seek(chs.cylinder, chs.head) catch |err| {
        // Neu kalibrieren und nochmal probiren
        try floppy_drive_recalibrate();
        try floppy_drive_seek(chs.cylinder, chs.head);
    };

    // DMA vorbereiten
    var dmaTransfer = if (use_dma) try ISA_DMA.beginWrite(FLOPPY_DMA_CHANNEL, buffer, .single) else {};
    defer if (use_dma) {
        dmaTransfer.close();
    };

    // // DMA-Buffer fuellen
    // if (cdi_dma_write(&dma_handle) != 0) {
    //     cdi_dma_close(&dma_handle);
    //     return -1;
    // }

    floppy_reset_irqcnt();
    // Befehl und Argumente senden
    // Byte 0: FLOPPY_CMD_WRITE
    // Byte 1: Bit 2:       Kopf (0 oder 1)
    //         Bits 0/1:    Laufwerk
    // Byte 2: Zylinder
    // Byte 3: Kopf
    // Byte 4: Sektornummer (bei Multisektortransfers des ersten Sektors)
    // Byte 5: Sektorgroesse (Nicht in bytes, sondern logarithmisch mit 0 fuer
    //                      128, 1 fuer 256 usw.)
    // Byte 6: Letzte Sektornummer in der aktuellen Spur
    // Byte 7: Gap Length
    // Byte 8: DTL (ignoriert, wenn Sektorgroesse != 0. 0xFF empfohlen)
    try floppy_write_data(FLOPPY_CMD_WRITE);
    try floppy_write_data((chs.head << 2) | drive.id);
    try floppy_write_data(chs.cylinder);
    try floppy_write_data(chs.head);
    try floppy_write_data(chs.sector);
    try floppy_write_data(FLOPPY_SECTOR_SIZE_CODE);
    try floppy_write_data(FLOPPY_SECTORS_PER_TRACK);
    try floppy_write_data(FLOPPY_GAP_LENGTH);
    try floppy_write_data(0xFF);

    // Wenn der Sektor geschrieben ist, kommt ein IRQ
    try floppy_wait_irq(FLOPPY_READ_TIMEOUT);

    // Die Rueckgabewerte kommen folgendermassen an:
    // Byte 0: Status 0
    // Byte 1: Status 1
    // Byte 2: Status 2
    // Byte 3: Zylinder
    // Byte 4: Kopf
    // Byte 5: Sektornummer
    // Byte 6: Sektorgroesse (siehe oben)

    const status = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();
    _ = try floppy_read_data();

    // Pruefen ob der Status in Ordnung ist
    if ((status & FLOPPY_ST0_IC_MASK) != FLOPPY_ST0_IC_NORMAL) {
        return error.GenericFailure;
    }
}

// Motorstatus setzen, also ein oder aus
fn floppy_drive_motor_set(state: MotorState) Error!void {
    const drive = try getCurrentDrive();

    if (drive.motor == state) {
        return; // already correct
    }

    // Wert des DOR sichern, weil nur das notwendige Bit ueberschrieben werden
    // soll.
    var dor = floppy_read_byte(FLOPPY_REG_DOR);
    var delay: usize = undefined;
    if (state == .on) {
        // Einschalten
        dor |= FLOPPY_DOR_MOTOR(drive);
        delay = FLOPPY_DELAY_SPINUP;
    } else {
        // Ausschalten
        dor &= ~FLOPPY_DOR_MOTOR(drive);
        delay = FLOPPY_DELAY_SPINDOWN;
    }
    floppy_write_byte(FLOPPY_REG_DOR, dor);

    // Dem Laufwerk Zeit geben, anzulaufen
    Timer.wait(delay);

    drive.motor = state;
    drive.current_cylinder = 255;
}

// Lese- und Schreibkopf des Diskettenlaufwerks auf einen neuen Zylinder
// einstellen
fn floppy_drive_seek(cylinder: u8, head: u8) Error!void {
    var drive = try getCurrentDrive();

    // Pruefen ob der Kopf nicht schon richtig steht, denn dann kann etwas Zeit
    // eingespart werden, indem nicht neu positioniert wird.
    if (drive.current_cylinder == cylinder) {
        return;
    }

    // Wenn der seek beendet ist, kommt ein irq an.
    floppy_reset_irqcnt();

    // Befehl und Attribute senden
    // Byte 0:  FLOPPY_CMD_SEEK
    // Byte 1:  Bit 0 und 1: Laufwerksnummer
    //          Bit 2: Head
    // Byte 2:
    try floppy_write_data(FLOPPY_CMD_SEEK);
    try floppy_write_data((head << 2) | drive.id);
    try floppy_write_data(cylinder);

    // Auf IRQ warten, der kommt, sobald der Kopf positioniert ist.
    try floppy_wait_irq(FLOPPY_SEEK_TIMEOUT);

    // Int sense holt die aktuelle Zylindernummer und teilt dem Kontroller mit,
    // dass sein IRQ abgearbeitet wurde. Die Zylindernummer wird benutzt, um
    // festzustellen ob der Seek erfolgreich verlief.
    try floppy_drive_int_sense();

    // Dem Kopf Zeit geben, sich sauber einzustellen
    Timer.wait(FLOPPY_SEEK_DELAY);

    // Warten bis das Laufwerk bereit ist

    var i: usize = 0;

    while (i < 5) : (i += 1) {
        const msr = floppy_read_byte(FLOPPY_REG_MSR);
        if ((msr & (FLOPPY_MSR_DRV_BSY(drive) | FLOPPY_MSR_CMD_BSY)) == 0) {
            break;
        }
        Timer.wait(FLOPPY_SEEK_DELAY);
    }

    // Wenn das Laufwerk nicht funktioniert muesste jetzt etwas dagegen
    // unternommen werden.
    if (i >= 5) {
        return error.GenericFailure;
    }

    // Pruefen ob der Seek geklappt hat anhand der neuen Zylinderangabge aus
    // int_sense
    if (drive.current_cylinder != cylinder) {
        TextTerminal.println("Fehler beim seek: Zylinder nach dem Seek nach {} ist {}\n", cylinder, drive.current_cylinder);
        return error.GenericFailure;
    }

    // Pruefen ob der Seek erfolgreich abgeschlossen wurde anhand des Seek-End
    // Bits im Statusregister
    if ((drive.current_status & FLOPPY_ST0_SEEK_END) != FLOPPY_ST0_SEEK_END) {
        return error.GenericFailure;
    }
}

fn floppy_write_data(data: u8) Error!void {
    // Wenn der Controller beschaeftigt ist, wird ein bisschen gewartet und
    // danach nochmal probiert
    var i: usize = 0;
    while (i < FLOPPY_WRITE_DATA_TRIES) : (i += 1) {
        const msr = floppy_read_byte(FLOPPY_REG_DSR);

        // Pruefen ob der Kontroller bereit ist, Daten von uns zu akzeptieren
        if ((msr & (FLOPPY_MSR_RQM | FLOPPY_MSR_DIO)) == (FLOPPY_MSR_RQM)) {
            floppy_write_byte(FLOPPY_REG_DATA, data);
            return;
        }
        Timer.wait(FLOPPY_READ_DATA_DELAY);
    }
    return error.GenericFailure;
}

fn floppy_read_data() Error!u8 {
    // Wenn der Controller beschaeftigt ist, wird ein bisschen gewartet und
    // danach nochmal probiert
    var i: usize = 0;
    while (i < FLOPPY_READ_DATA_TRIES) : (i += 1) {
        const msr = floppy_read_byte(FLOPPY_REG_DSR);

        // Pruefen ob der Kontroller bereit ist, und Daten zum abholen
        // bereitliegen.
        if ((msr & (FLOPPY_MSR_RQM | FLOPPY_MSR_DIO)) == (FLOPPY_MSR_RQM | FLOPPY_MSR_DIO)) {
            return floppy_read_byte(FLOPPY_REG_DATA);
        }
        Timer.wait(FLOPPY_READ_DATA_DELAY);
    }
    return error.GenericFailure;
}

fn floppy_read_byte(reg: u16) u8 {
    return IO.in(u8, reg);
}

fn floppy_write_byte(reg: u16, value: u8) void {
    IO.out(u8, reg, value);
}

const FLOPPY_REG_DOR = 0x3F2;
const FLOPPY_REG_MSR = 0x3F4;
const FLOPPY_REG_DSR = 0x3F4;
const FLOPPY_REG_DATA = 0x3F5;

const FLOPPY_CMD_CONFIGURE: u8 = 19;
const FLOPPY_DOR_DRIVE_MASK: u8 = 3;
const FLOPPY_CMD_INT_SENSE: u8 = 8;
const FLOPPY_FIFO_SIZE: u8 = 16;
const FLOPPY_DOR_NRST: u8 = 1 << 2;
const FLOPPY_DSR_500KBPS: u8 = 0;
const FLOPPY_DOR_DMAGATE: u8 = 1 << 3;
const FLOPPY_DSR_300KBPS: u8 = 1;
const FLOPPY_DSR_1MBPS: u8 = 3;
const FLOPPY_MSR_RQM: u8 = 1 << 7;
const FLOPPY_CMD_SEEK: u8 = 15;
const FLOPPY_DSR_250KBPS: u8 = 2;
const FLOPPY_CMD_SPECIFY: u8 = 3;
const FLOPPY_CMD_READ: u8 = 70;
const FLOPPY_ST0_IC_NORMAL: u8 = 0 << 6;
const FLOPPY_CMD_WRITE: u8 = 69;
const FLOPPY_FIFO_THRESHOLD: u8 = 4;
const FLOPPY_MSR_DIO: u8 = 1 << 6;
const FLOPPY_ST0_SEEK_END: u8 = 1 << 5;
const FLOPPY_ST0_IC_MASK: u8 = 3 << 6;
const FLOPPY_CMD_RECALIBRATE: u8 = 7;
const FLOPPY_MSR_CMD_BSY: u8 = 1 << 4;

const FLOPPY_READ_TIMEOUT = 200;
const FLOPPY_DMA_CHANNEL = 2;
const FLOPPY_RECAL_TIMEOUT = 100;
const FLOPPY_READ_DATA_TRIES = 50;
const FLOPPY_SEEK_DELAY = 15;
const FLOPPY_DELAY_SPINUP = 500;
const FLOPPY_SEEK_TIMEOUT = 100;
const FLOPPY_WRITE_DATA_DELAY = 10;
const FLOPPY_WRITE_DATA_TRIES = 50;
const FLOPPY_SECTOR_SIZE_CODE = 2;
const FLOPPY_HEAD_COUNT = 2;
const FLOPPY_SECTORS_PER_TRACK = 18;
const FLOPPY_DATA_RATE = 500000;
const FLOPPY_SECTOR_COUNT = 2880;
const FLOPPY_READ_DATA_DELAY = 10;
const FLOPPY_RESET_TIMEOUT = 100;
const FLOPPY_RECAL_TRIES = 5;
const FLOPPY_SECTOR_SIZE = 512;
const FLOPPY_DELAY_SPINDOWN = 500;
const FLOPPY_GAP_LENGTH = 27;

fn FLOPPY_DOR_MOTOR(drive: *const Drive) u8 {
    return (@as(u8, 1) << (4 + @as(u3, drive.id)));
}
fn FLOPPY_DOR_DRIVE(drive: *const Drive) u8 {
    return (drive.id);
}
fn FLOPPY_MSR_DRV_BSY(drive: *const Drive) u8 {
    return (@as(u8, 1) << (drive.id));
}
