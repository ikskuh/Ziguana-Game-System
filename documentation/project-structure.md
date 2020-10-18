# ZPAK Game ROM

This file is a [GNU TAR](https://www.gnu.org/software/tar/manual/html_node/Standard.html) file which contains all relevant parts of a game.

The file follows this rough structure:

```
.
├── game.lm
├── game.ico
├── game.name
├── game.id
└── data/
    ├── some_file.dat
    └── other_file.icon
```

- `game.lm` is the game source code, a LoLa compile unit.
- `game.ico` is a 24×24 pixel icon file, encoded in the usual [bitmap format](bitmap-format.md). If this file is not given, a default icon is shown.
- `game.name` is a file containing the display name of the game which will be shown in the game discovery.
- `game.id` is a unique game identifier. This follows the java package conventions and is the creators domain backwards. If this file is not given, the user is not able to save/load files. Example: `net.random-projects.zgs.example`
- `data/` is a folder containing embedded resources of the game. These files can be load with the `LoadData()` API.
