# Ziguana Game System API

## System Control

### `Poweroff() noreturn`

Will shut down the console and exit.

### `SaveGame(data: string) bool`

Opens a prompt for the user to save the game. The user can then select one of three save games to save the game or cancel the saving process.
Returns `true` when the game was successfully saved, otherwise `false`.

### `LoadGame() string|void`

Opens a prompt for the user to load a previously saved game. The user can then select one of the save games or cancel the loading.
When the user selected a save game, the data is returned as a `string`, if the user cancelled the saving, `void` is returned.

### `Pause() void`

Opens the pause screen of the console. The user can then decide to resume the game at any time.

## Resource Management

### `LoadData(path: string) string|void`

Will load a resource located at `"data/" + path`

## Text Mode

This is the default mode of the system. It displays a primitive text terminal with 20×15 characters of size and a small 6×6 pixel font.

### `Print(…): void`

Prints all arguments followed by a new line.

### `Input(prompt: string|void) string|void`

Asks the user for a value accepted by _Return_ or cancelled by _Escape_. If _Return_ is pressed, the user accepted the input and a string is returned, if _Escape_ was pressed, the user cancelled the input and `void` is returned.

The function will go into a new line if not already and will print `prompt` if given. If not, `? ` is printed as a prompt.

### `TxtClear(): void`

Clears the screen and resets the cursor to the top-left.

### `TxtSetBackground(color: number) void`

Sets the background color of the screen. The color parameter is explained in [Graphics Mode](#Graphics_Mode).

### `TxtSetForeground(color: number) void`

Sets the text color. All new text is written in that color. The color parameter is explained in [Graphics Mode](#Graphics_Mode).

### `TxtWrite(…): number`

Writes the arguments to the text console and returns the number of characters written.

### `TxtRead(): string`

Reads all available text from the keyboard buffer. Returns `""` when nothing is in the buffer.

### `TxtReadLine(): string|void`

Reads a line of text entered by the user. As soon as the user presses _Return_, the text is returned. If `""` is returned, the user pressed _Return_, but didn't enter text. If `void` is returned, the user cancelled the input by pressing _Escape_.

### `TxtEnableCursor(enabled: bool) void`

Enables or disables the text cursor. The text cursor will always be one digit behind the last printed character and will blink.

### `TxtSetCursor(x: number, y: number) void`

Moves the cursor on the screen. New text will be inserted at the cursor position, even if the cursor is not visible.

### `TxtScroll(lines: number) void`

Scrolls the text screen by the given number of lines.

## Graphics Mode

The system also provides a bitmap mode with a resolution of 120×90 pixels and 4 bit color depth and a fixed palette.

Pixels are encoded as bytes in a string, where each byte encodes a color between 0 and 15. If the byte value is larger than 15, the pixel is considered _broken_ and will display a randomly changing color from the palette.

### `SetGraphicsMode(enabled: bool) void`

If `enabled == true`, the system will enable graphics mode, otherwise it will enable text mode.

### `GpuSetPixel(x: number, y: number, color: number|void) void`

Sets the pixel at (`x`, `y`) to `c` where `c` is a number between `0` and `15` or `void` for a broken pixel.

### `GpuGetPixel(x: number, y: number) number|void`

Returns the color index of a pixel at (`x`, `y`) or `void` if the pixel is broken.

### `GpuGetFramebuffer(): string`

Returns a string of length 10800 where each byte corresponds to a pixel on the screen. Valid pixels are encoded as values `0` … `15`, broken pixels are encoded as `255`.

### `GpuSetFramebuffer(fb: string) void`

Sets the frame buffer to the given string. Each byte is considered a pixel value. Excess bytes (more than 10800) are cut off, missing bytes (less than 10800) are filled with _broken_ pixels. Each byte may have a integer value between `0` and `15` or be a valid hexadecimal digit (`'0'`…`'9'`, `'a'`…`'f'`, `'A'`…`'F'`), all other values are considered _broken_.

### `GpuBlitBuffer(x: number, y: number, width: number, data: string) void`

Copies pixels from `data` onto the screen. The rules for the pixel format are the same as in `GpuSetFramebuffer`, except that _broken_ pixels are ignored and will not be blitted into the framebuffer.

Pixels are copied starting at point (`x`, `y`), where both coordinates may be negative. Pixels are then copied to the right for `width` pixels, then advance one row and continue copying. Pixels that are out-of-screen are discarded, no wrap-around is performed.

This routine allows simple sprite or tile graphics to be done.

### `GpuDrawLine(x0, y0, x1, y1, c)`

Draws a Line from (`x0`, `y0`) to (`x1`, `y1`) with color `c`.

### `GpuDrawRect(x, y, w, h, c)`s

Draws the rectangle outline between the points (`x`, `y`) and (`x+w-1`,`y+h-1`) with color `c`.

### `GpuFillRect(x, y, w, h, c)`

Fills the rectangle between the points (`x`, `y`) and (`x+w-1`,`y+h-1`) with color `c`.

### `GpuDrawText(x, y, text)`

Draws a string `text ` starting at (`x`, `y`). The font size is 6×6 pixels, which gives a maximum text density of 20×15 characters.

### `GpuScroll(dx, dy)`

Scrolls the screen content by the given amount into x and y direction. Contents that get shifted out of the screen will be shifted in on the opposite site again. This rolls the screen content.

This is helpful for scrolling backgrounds and similar.

### `GpuSetBorder(color: number) void`

Sets the background color of the border around the screen.

### `GpuFlush() void`

Will flush the current framebuffer to the screen and wait for vsync.

### `GpuEnableAutoFlush(enabled: bool) void`

If `enabled` is true, the graphics functions will always draw directly to the screen and when vsync comes, the result will be presented.

## Keyboard

### Key Map

> To be done

### `KbdIsDown(key: string) bool`

Returns `true` when the `key` is pressed.

### `KbdIsUp(key: string) bool`

Returns `true` when the `key` is not pressed.

## Joystick

Input API for a connected joystick. The joystick has a analogue stick and two buttons _A_ and _B_.

### `JoyEnableNormalization(enabled: bool) void`

If `enabled` is true, the values returned by `JoyGetX` and `JoyGetY` will always have a euclidean length of `<= 1.0`. Otherwise, the axis will be separated and both have the full range.

### `JoyGetX(): number`

Returns a value between `-1.0` and `1.0` that reflects the horizontal position of the joystick. Negative values go left, positive values go right.

### `JoyGetY(): number`

Returns a value between `-1.0` and `1.0` that reflects the vertical position of the joystick. Negative values are upwards, positive values go downwards.

### `JoyGetA(): bool`

Returns `true` when the _A_ button is pressed.

### `JoyGetB(): bool`

Returns `true` when the _B_ button is pressed.

## Audio System

### `PlaySound(name: string, volume: number) void`

Plays a sound called `name` with the given `volume` (between `0.0` and `1.0`).

### `LoopSound(name: string, volume: number) object`

Plays a sound in a loop and returns a handle to the playing sound. The loop can be controlled via this handle:

#### `SoundHandle.Stop() void`

Will stop the loop from playing and will make the sound handle invalid (destroys the object).

#### `SoundHandle.Pause() void`

Will stop the loop from playing at the current position.

#### `SoundHandle.Resume() void`

Lets a paused loop continue to play

#### `SoundHandle.SetVolume(volume: number) void`

Will change the volume of the loop.

### `PlayMusic(music: string, fade_time: number) void`

Starts playing the track `music`, stopping all previously played music.
The tracks will smoothly fade one into the other over `fade_time` seconds. If `fade_time` is not given, 0.5 seconds will be used to fade the tracks.
