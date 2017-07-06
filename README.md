# lime-vscode-extension

_This extension is a work in-progress_

## Setup

### Install Visual Studio Code, Insider Build
 
Go to https://code.visualstudio.com/insiders and install
 
### Disable auto-updates

Open the Insider's Build, then go to "Preferences" > "Settings". This will open a text editor.

In the window, add the following value:

```json
"extensions.autoUpdate": false
```

This will prevent an auto-update mechanism that will install a release version of vshaxe, breaking the development version
 
### Install a custom version of the vshaxe extension

The current version of vshaxe lacks an extension API needed for lime-vscode to work properly. This is how to clone and build a custom fork for now 

##### Windows

```bash
cd C:\Users\(your user name)\.vscode-insiders\extensions
```

##### macOS/Linux

```bash
 cd ~/.vscode-insiders/extensions
```

then:

```bash
git clone -b api --recursive https://github.com/jgranick/vshaxe
haxelib git vshaxe-build https://github.com/vshaxe/vshaxe-build
cd vshaxe
haxelib run vshaxe-build --target vshaxe --debug --mode both
cd ..
```

### Install and build this extension

In the "extensions" directory:

```bash
git clone --recursive https://github.com/openfl/lime-vscode-extension
```

### Build the extension

If you do not want to debug the extension, you should build it at least once:

```bash
cd lime-vscode-extension
haxe build.hxml
```

### Development workflow

Otherwise, you can open the "lime-vscode-extension" directory using Visual Studio Code. This enables a development workflow, where you can use `Ctrl`+`Shift`+`B` (`Cmd`+`Shift`+`B` on Mac) to open the build command, and hit `Enter` to recompile the extension.

Hit `F5` to begin debugging. This opens another Visual Studio Code window with the extension enabled. Errors, log output and other data will be reported back to the "Debug Console" in the first window

## Using the extension

Open a folder that contains a Lime project file, and the extension should become active.

The lower-left part of the window should include status bar items for the current build target, configuration (release, debug or final) as well as an option for additional flags or defines.

You can change them by clicking, and selecting a new option in the pop-up. Code completion should be working, but may require a update or build first.

You should be able to use `Ctrl`+`Shift`+`B` (`Cmd`+`Shift`+`B` on Mac) to access the Lime build task. There is also a "Run Test" command you can use, but it has no keyboard shortcut. I set mine to `Ctrl`+`Enter` (`Cmd`+`Enter`) for accessing Lime test.
