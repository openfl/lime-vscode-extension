# Change Log

1.5.0 (02/??/2023)
------------------

* Improved messaging when `lime display` command fails. Does not suggest `lime setup` as frequently, and displays the full error text in an output channel instead of devtools.
* Fixed HashLink debugging for Lime 8.0.0
* Fixed web browser launching with wrong port if HTML5 target flags includes a customized `--port` option
* Debugging in Flash Player defaults to "Flash Debugger" extension, but may also use "Debugger for SWF" extension
* Added support for Adobe AIR debugging if "Debugger for SWF" extension is installed

1.4.3 (09/28/2021)
------------------

* Updated HTML5 debugging to use built-in Edge and Chrome debuggers
 

1.4.2 (12/21/2020)
------------------

* Fixed support for `lime.projectFile` at the top-level of the workspace


1.4.1 (12/21/2020)
------------------

* Improved display arguments to update when `lime.projectFile` changes
* Fixed the current working directory when using `lime.projectFile` in a sub-directory


1.4.0 (04/14/2020)
------------------

* Added support for running `lime update` on project changes
* Added `lime.promptToRefreshCompletion` to disable automatic updating
* Added initial support for HashLink debugging

1.3.2 (03/02/2020)
------------------

* Improved switching from `"lime test"` task to debug session
* Fixed backward compatibility with some older Lime versions
* Fixed support for newer VSCode plugin interface
* Updated ID for Firefox debugger extension


1.3.1 (04/04/2019)
------------------

* Added support for installing missing debugger extensions (VSCode 1.33)
* Improved the `"lime"` debug adapter to not set `"preLaunchTask"` if already specified
* Restored the target flag status bar item instead of the verbose toggle
* Fixed incorrect shell command when using the "lime.projectFile" setting


1.3.0 (04/01/2019)
------------------

* Added initial support for compatibility with HXCPP, Flash and HTML5 debuggers (requires Lime 7.3)
* Added support for "target configurations" (target + build type + optional arguments)
* Merged the target and build type status bar items into a single target configuration option
* Replaced the additional arguments status bar item with a toggle for verbose output
* Added "lime.targets" setting to add or disable Lime targets in the UI
* Added "lime.buildTypes" setting to disable standard build types (Release, Debug, etc) or add new custom types
* Added "lime.defaultTargetConfiguration" setting for the default configuration in new workspaces
* Added "lime.targetConfigurations" setting to disable default configurations or add new custom configurations
* Added "lime.browser" setting to select the browser used for debugging HTML5
* Updated the task provider to persist available tasks regardless of the currently selected configuration

1.2.2 (02/07/2019)
------------------

* Updated the minimum required VSCode version to 1.31.0
* Added support for `showReuseMessage` and `clear` in `haxe.taskPresentation` ([#46](https://github.com/openfl/lime-vscode-extension/issues/46))
* Worked around tasks not working with VSCode 1.31.0 ([vscode#67990](https://github.com/Microsoft/vscode/issues/67990))

1.2.1 (03/05/2018)
------------------

* Updated the minimum required VSCode version to 1.20.0
* Fixed target flags being cleared when the input prompt is canceled ([#40](https://github.com/openfl/lime-vscode-extension/issues/40))
* Changed the target flags status bar item to show the flags in the tooltip ([#40](https://github.com/openfl/lime-vscode-extension/issues/40))

1.2.0 (04/20/2018)
------------------

* Added support for the `haxe.taskPresentation` setting in vshaxe 1.11.0 ([#31](https://github.com/openfl/lime-vscode-extension/issues/31))
* Added support for the new problem matchers in vshaxe 1.11.0 ([#31](https://github.com/openfl/lime-vscode-extension/issues/31))
* Added `lime.executable` for using a custom Lime command ([#36](https://github.com/openfl/lime-vscode-extension/issues/36))
* Added an error message in case the `lime display` command fails ([#36](https://github.com/openfl/lime-vscode-extension/issues/36))


1.1.0 (04/04/2018)
------------------

* Added `lime.defaultTarget` for use when opening a new workspace ([#27](https://github.com/openfl/lime-vscode-extension/issues/27))
* Added `lime.defaultBuildConfiguration` as well for new workspaces ([#27](https://github.com/openfl/lime-vscode-extension/issues/27))
* Added support for sharing the compilation server with the Haxe extension ([#28](https://github.com/openfl/lime-vscode-extension/issues/28))


1.0.8 (11/10/2017)
------------------

* Added AIR as a selectable target in the UI
* Minor fixes
