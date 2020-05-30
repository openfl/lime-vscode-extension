package lime.extension;

class DisplayArgsProvider
{
	public var description(default, never):String = "Project using Lime/OpenFL command-line tools";
	public var parsedArguments(default, null):Array<String>;

	private var activationChangedCallback:Bool->Void;
	private var api:Vshaxe;
	private var arguments:String;

	private var updateArgumentsCallback:Array<String>->Void;

	public function new(api:Vshaxe, activationChangedCallback:Bool->Void)
	{
		this.api = api;
		this.activationChangedCallback = activationChangedCallback;
	}

	public function activate(provideArguments:Array<String>->Void):Void
	{
		updateArgumentsCallback = provideArguments;

		if (parsedArguments != null)
		{
			updateArguments();
		}

		activationChangedCallback(true);
	}

	public function deactivate():Void
	{
		updateArgumentsCallback = null;

		activationChangedCallback(false);
	}

	public function update(arguments:String):Void
	{
		if (this.arguments != arguments && api != null)
		{
			this.arguments = arguments;
			this.parsedArguments = api.parseHxmlToArguments(arguments);

			updateArguments();
		}
	}

	private function updateArguments()
	{
		if (updateArgumentsCallback != null)
		{
			updateArgumentsCallback(parsedArguments);
		}
	}
}
