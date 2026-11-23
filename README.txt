SNATCHER ACCESS, version 0.27
A screen reader mod for Snatcher (USA, Sega CD), played in the BizHawk emulator.
It reads the game aloud so blind players can play it from start to finish.

This download contains only the mod. It does not include BizHawk, the Sega CD
BIOS, or the game. You need your own copies of all three.

WHAT YOU NEED
1. BizHawk for Windows, a recent version that can open CHD files
   (made with BizHawk 2.11).
2. The USA Sega CD BIOS, set up in BizHawk (Config menu, Firmwares).
3. Your own Snatcher (USA) Sega CD disc image, as a .chd file or a .cue file
   with its .bin files.

INSTALLING
1. Unzip this folder anywhere, for example inside your BizHawk folder.
   Keep snatcher-access.lua, prism.dll and the sounds folder together.
2. Open BizHawk and load your Snatcher (USA) disc image.
3. Open the Tools menu, then Lua Console.
4. In the Lua Console, open the Script menu, choose Open Script, and pick
   snatcher-access.lua.
5. You hear Snatcher Access say that it is ready, with its version number. Go back to the game window.

SPEECH
The mod speaks through Prism (prism.dll, included), which works with NVDA,
JAWS, Narrator and other screen readers, or a Windows voice if no screen
reader is running. If Prism cannot start, it uses BizHawk's own speech if
your BizHawk has it, and otherwise the Windows voice.
Everything said is also written to snatcher-speech.log next to the script.

IF YOU HEAR NO SPEECH
Every time the script starts, it writes snatcher-debug.log next to
snatcher-access.lua. It says which voice the mod found and why any of them
failed. Please send snatcher-debug.log and snatcher-speech.log with your
report. The BizHawk Lua Console shows the same messages.

STARTING THE GAME
At the backup memory question, choose Internal backup RAM (Up and Down,
then Start). At the title screen choose New game or Continue with Up and
Down, then press Start. New game opens Options: move down to Quit and press
C to begin. Continue lists your investigation files with play time and number
of saves; choose one and press Start, then go to Quit in Options and press C.

GAME CONTROLS
Snatcher uses three buttons. By default:
  C: select a command, advance text, and shoot.
  B: cancel, go back out of a menu.
  A: draw or put away your blaster in shooting scenes.
  Start: start, and skip some cut scenes.
The layout can be changed in Options, Controls; the mod follows it.

WHAT IS READ
Every line of text with the speaker's name. Every command menu and list,
with the position, like "Look, 2 of 5". The backup memory question, the
title choice, the investigation files, and every Options setting. Save slots,
the computer Jordan, and the game over menu.
Picture words in the opening: the dedication, place and date captions, the
cast and staff credits, and the Junker Headquarters caption.
Voiced scenes have no text in this version of the game, so the mod stays
quiet while the actors speak.

SHOOTING SCENES
Enemies appear in one of nine spots: up left, up, up right, left, center,
right, down left, down, down right. Each one is spoken ("Enemy up left",
"Civilian right, don't shoot") and plays a sound: left and right in your
headphones match the screen, high pitch is the top row, low is the bottom.
Enemies beep from where they are, over and over, slowly at first and faster
the longer they stay. Only the enemy that has been there longest beeps (where
aim assist points); a newer one gives a single beep. Civilians make one soft
falling tone.
AIM ASSIST is on by default (G turns it off and on). It draws your blaster
at the start of each shooting scene and points your aim at the oldest enemy,
so you only press C when you hear "Enemy". Your own D pad always overrides
it, and it never aims at civilians. Without it: press A to draw, hold the D
pad toward the target (both directions for corners, nothing for the center)
and press C. A short chime means you destroyed an enemy.
Getting hit plays a buzz and says your life, like "Hit! Life 4".
The Junker HQ shooting range uses the same nine spots, so practise there.

VIDEOPHONE
Use Metal Gear, Videophone, Call. Arrows move between keys and each key is
spoken. C types a key and reads back the number so far. B deletes a digit.
The call goes through as soon as you type a number the game knows.

AUTOMATIC UPDATES
Each time the script starts, it checks GitHub for a newer published release
of Snatcher Access. If there is one, it says "Downloading Snatcher Access"
and the version, downloads the new files, checks them, replaces the old ones
and restarts itself. If you are offline or anything goes wrong, nothing is
changed and the game carries on. To turn updates off, put an empty file
called no-update.txt next to snatcher-access.lua.

KEYBOARD KEYS
R: repeat the last thing said.
T: read the current message again.
M: read the whole menu or the current choice on special screens.
L: life and targets in a shooting scene.
V: spoken target positions on or off.
B: target sounds on or off.
G: aim assist on or off.
Control: stop speech.
K: help.

KNOWN LIMITS
Picture captions later in the game, after the opening, are not read yet.
The act number on the investigation files is not read.

PRISM
Speech uses Prism (github.com/ethindp/prism), licensed under the Mozilla Public
License 2.0. Its licence and the licences of the parts it uses are in the
prism-licences folder.
