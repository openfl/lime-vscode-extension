![](https://github.com/openfl/lime-vscode-extension/raw/master/images/screenshot.png)

# Visual Studio Code Support for Lime/OpenFL

The Lime extension for Visual Studio Code adds code completion, inline documentation, 
populates the Haxe dependency tree and provides build, clean, test and (other) tasks automatically.

This depends on the Haxe extension, and requires Haxe 3.4.2 or greater. You should also have
Lime installed and properly set up.

Opening a folder that contains a `project.xml`, `project.hxp` or `project.lime` file activates
this extension. Optionally, you can set `"lime.projectFile"` in the workspace `settings.json`
file in order to specify a different file path. When activated, this extension adds support for
changing the target platform, build configuration as well as additional command-line arguments.

# About Lime

Lime is a flexible, cross-platform framework for native desktop, mobile and console development,
and Flash, HTML5 and WebAssembly.

OpenFL is a productive 2D library built on Lime. More information about Lime and OpenFL are 
available at [http://www.openfl.org](http://www.openfl.org)

# Feedback

For questions, comments or concerns, please visit the forums at [http://community.openfl.org](http://community.openfl.org)

# Using Development Builds

### Install Visual Studio Code
 
Go to https://code.visualstudio.com/download and install
 
### Disable auto-updates

Open Visual Studio Code, then go to "Preferences" > "Settings". This will open a text editor.

In the window, add the following value:

```json
"extensions.autoUpdate": false
```

This will prevent an auto-update mechanism that will install a release version of vshaxe and lime-vscode-extension, breaking the development version

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

Otherwise, you can open the "lime-vscode-extension" directory using Visual Studio Code. This enables a development workflow, where you can use <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> (<kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> on Mac) to recompile the extension.

Hit <kbd>F5</kbd> to begin debugging. This opens a second Visual Studio Code window with the extension enabled. Errors, log output and other data will be reported back to the "Debug Console" in the first window.

## Using the extension

Open a folder that contains a Lime project file, and the extension should become active.

The lower-left part of the window should include status bar items for the current build target, configuration (release, debug or final) as well as an option for additional flags or defines.

You can change them by clicking, and selecting a new option in the pop-up. Code completion should be working, but may require a update or build first.

You should be able to use <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> (<kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> on Mac) to access the `lime build` task. There is also a "Run Test" command you can use, but it has no keyboard shortcut. One option would be to set "Run Test Task" in keyboard shortcuts to <kbd>Ctrl</kbd>+<kbd>Enter</kbd> (<kbd>Cmd</kbd>+<kbd>Enter</kbd>) for accessing `lime test` quickly.
