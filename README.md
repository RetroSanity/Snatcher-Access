# Snatcher Access

A screen reader mod for **Snatcher** (USA, Sega CD), played in the [BizHawk](https://github.com/TASEmulators/BizHawk) emulator. It reads the game aloud so blind players can play it from start to finish.

This repository contains only the mod. It does not include BizHawk, the Sega CD BIOS, or the game. You need your own copies of all three.

## Download

Get the latest zip from the [Releases page](../../releases/latest).

## What you need

1. BizHawk for Windows, a recent version that can open CHD files (made with BizHawk 2.11).
2. The USA Sega CD BIOS, set up in BizHawk (Config menu, Firmwares).
3. Your own Snatcher (USA) Sega CD disc image, as a .chd file or a .cue file with its .bin files.

## Installing

1. Unzip the release anywhere, for example inside your BizHawk folder. Keep `snatcher-access.lua`, `prism.dll` and the `sounds` folder together.
2. Open BizHawk and load your Snatcher (USA) disc image.
3. Open the Tools menu, then Lua Console.
4. In the Lua Console, open the Script menu, choose Open Script, and pick `snatcher-access.lua`.
5. You hear Snatcher Access say that it is ready, with its version number. Go back to the game window.

## Speech

The mod speaks through [Prism](https://github.com/ethindp/prism) (`prism.dll`, included), which works with NVDA, JAWS, Narrator and other screen readers, or a Windows voice if no screen reader is running. If Prism cannot start, the mod uses BizHawk's own speech if your BizHawk has it (`speech.say`), and otherwise the Windows voice. Everything said is also written to `snatcher-speech.log` next to the script.

### No speech?

Every time the script starts, it writes `snatcher-debug.log` next to `snatcher-access.lua`. It records which voice the mod found (Prism, BizHawk speech or the Windows voice) and why any of them failed. Please attach `snatcher-debug.log` and `snatcher-speech.log` when you report a problem.

## Starting the game

At the backup memory question, choose Internal backup RAM (Up and Down, then Start). At the title screen choose New game or Continue with Up and Down, then press Start.

- **New game** opens Options. Move down to Quit and press C to begin.
- **Continue** lists your investigation files with play time and number of saves. Choose one and press Start, then go to Quit in Options and press C.

## Game controls

Snatcher uses three buttons. By default:

- **C**: select a command, advance text, and shoot.
- **B**: cancel, go back out of a menu.
- **A**: draw or put away your blaster in shooting scenes.
- **Start**: start, and skip some cut scenes.

The layout can be changed in Options, Controls. The mod follows it, including when the game names a button.

## What is read

- Every line of text, with the speaker's name.
- Every command menu and list, with the position, like "Look, 2 of 5".
- The backup memory question, the title choice, the investigation files, and every Options setting.
- Save slots, the computer Jordan, and the game over menu.
- Picture words in the opening: the dedication, place and date captions, the cast and staff credits, and the Junker Headquarters caption.

Voiced scenes have no text in this version of the game, so the mod stays quiet while the actors speak.

## Shooting scenes

Enemies appear in one of nine spots: up left, up, up right, left, center, right, down left, down, down right. Each one is spoken ("Enemy up left", "Civilian right, don't shoot") and plays a sound. Left and right in your headphones match the screen. A high pitch is the top row and a low pitch is the bottom.

Enemies beep from where they are, over and over: slowly at first, then faster the longer the enemy stays, because enemies attack if left too long. Only one enemy beeps at a time, the one that has been there longest (where aim assist points); a newer enemy gives a single beep from its spot. Civilians make one soft falling tone.

**Aim assist** is on by default (G turns it off and on). At the start of each shooting scene it draws your blaster for you ("Blaster ready"), and it points your aim at the oldest enemy on screen, so you only need to press C when you hear "Enemy". Holding the D pad yourself always overrides it, and it never aims at civilians.

Without aim assist: press A to draw your blaster, hold the D pad toward the target (both directions for corners, nothing for the center) and press C to shoot.

A short chime means you destroyed an enemy. Shooting a civilian says "You shot a civilian!". Getting hit plays a buzz and says your life, like "Hit! Life 4".

The Junker HQ shooting range uses the same nine spots, so practise there.

## Videophone

Choose Use Metal Gear, Videophone, Call. The arrows move between keys and each key is spoken. C types a key and reads back the number so far. B deletes a digit. The call goes through as soon as you type a number the game knows.

## Automatic updates

Each time the script starts, it checks this repository for a newer published release. If there is one, it says "Downloading Snatcher Access" and the version, downloads the new files listed in that release's `manifest.txt`, checks their sizes, replaces the old files and restarts itself. Only published releases are installed. If you are offline or anything goes wrong, nothing is changed. To turn updates off, put an empty file called `no-update.txt` next to `snatcher-access.lua`.

## Keyboard keys

| Key | What it does |
| --- | --- |
| R | Repeat the last thing said |
| T | Read the current message again |
| M | Read the whole menu, or the current choice on special screens |
| L | Life and targets in a shooting scene |
| V | Spoken target positions on or off |
| B | Target sounds on or off |
| G | Aim assist on or off |
| Control | Stop speech |
| K | Help |

## Known limits

- Picture captions later in the game, after the opening, are not read yet.
- The act number on the investigation files is not read.

If a screen is silent, please open an issue saying what it was and what you did to get there.

## Credits

Speech uses [Prism](https://github.com/ethindp/prism), licensed under the Mozilla Public License 2.0. Its licence and the licences of the parts it uses are in the `prism-licences` folder.
