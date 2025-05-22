![](https://github.com/openfl/lime-vscode-extension/raw/master/images/screenshot.png)

# Visual Studio Code Support for Lime/OpenFL

With the Lime extension for Visual Studio Code, developers can open
[Haxe](https://haxe.org/) projects that use the [Lime](https://lime.openfl.org/)
and [OpenFL](https://openfl.org/) libraries. You'll get code completion and
inline documentation, a fully populated Haxe dependency tree, and the ability to
run tasks to build, clean, and test your projects.

You can also use this extension to develop projects that depend on popula
 OpenFL libraries, including [HaxeFlixel](https://haxeflixel.com/),
[Starling](https://github.com/openfl/starling) and
[Away3D](https://github.com/openfl/away3d).

The Lime extension integrates directly with the official
[Haxe extension](https://marketplace.visualstudio.com/items?itemName=nadako.vshaxe),
and Haxe 3.4.2 or greater is required (but Haxe 4.0 or newer is recommended). Be
sure to install [Lime](https://lib.haxe.org/p/lime) from Haxelib and run the
`haxelib run lime setup` command to configure it.

Opening a folder that contains a `project.xml`, `project.hxp` or `project.lime`
file activates this extension. Optionally, you can set `"lime.projectFile"` in
the workspace `.vscode/settings.json` file in order to specify a different file
path. When activated, this extension adds support for changing the target
platform, the build configuration, as well as additional command-line arguments.

# About Lime

[Lime](https://lime.openfl.org/) is a flexible, cross-platform framework for
native desktop, mobile and console development, including support for
cross-platform technologies like HTML5, WebAssembly, Electron, HashLink, and
Adobe AIR.

[OpenFL](https://openfl.org/) is a library for creative expression that
reimplements the display list, event system, audio and video playback, enhanced
GPU support with Stage 3D, and more from Adobe Flash Player and AIR. OpenFL is
built on Lime, which means that it can reach platforms everywhere.

To learn more about Lime and OpenFL, visit
[https://www.openfl.org](https://www.openfl.org).

# Feedback

For questions, comments or concerns, please visit the forums at
[https://community.openfl.org](https://community.openfl.org)

## Using the extension

Open a folder that contains a Lime project file named `project.xml`,
`project.hxp` or `project.lime`, and the extension should become active.

The lower-left part of the window should include status bar items for the
current build target (such as HTML5, Windows, Mac, or Linux), configuration
(Release, Debug or Final) as well as an item that allows you to specify
additional flags or defines.

You can change them by clicking, and selecting a new option in the pop-up. Code
completion should be working automatically, but may require a update or build
task to be run first.

You should be able to use <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd>
(<kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> on Mac) to access the `lime build`
task. There is also a "Run Test" command you can use, but it has no keyboard
shortcut. One option would be to set "Run Test Task" in keyboard shortcuts to
<kbd>Ctrl</kbd>+<kbd>Enter</kbd> (<kbd>Cmd</kbd>+<kbd>Enter</kbd>) for accessing
`lime test` quickly.


## Using Development Builds

### Install Visual Studio Code
 
Go to https://code.visualstudio.com/download and install.
 
### Disable auto-updates

Open Visual Studio Code, then go to "Preferences" > "Settings". This will open a
text editor.

In the window, add the following value:

```json
"extensions.autoUpdate": false
```

This will prevent an auto-update mechanism that will install a release version
of vshaxe and lime-vscode-extension, breaking the development version.

### Install and build this extension

In the "extensions" directory:

```bash
git clone --recursive https://github.com/openfl/lime-vscode-extension
cd lime-vscode-extension
npm install
```

### Build the extension

If you do not want to debug the extension, you should build it at least once:

```bash
cd lime-vscode-extension
npm run build -s
```

### Development workflow

Otherwise, you can open the "lime-vscode-extension" directory using Visual
Studio Code. This enables a development workflow, where you can use
<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd>
(<kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> on Mac) to recompile the
extension.

Hit <kbd>F5</kbd> to begin debugging. This opens a second Visual Studio Code
window with the extension enabled. Errors, log output and other data will be
reported back to the "Debug Console" in the first window.
