# ZGS Bitmap Format

The bitmap format is pretty simple:
Each pixel is encoded by a single byte, pixels are encoded either in binary (value `0`…`15`) or as hexadecimal characters (`'0'`…`'9'`, `'a'`…`'f'`, `'A'`…`'F'`). Values outside this range will be considered *broken* and are either displayed as a flimmering pixel or will be considered transparent.

Pixels are encoded row-major, so pixels will be in order left-to-right, then top-to-bottom.

Example for a 8×8 texture encoding a two-colored 'A' character:

```
..0000..
.0....1.
.0....1.
.000111.
.0....1.
.0....1.
.1....1.
........
```
(note that the LF displayed here is only for visualization and should not be included in the final file)

The size of the bitmaps is not encoded in the file format itself.