package lime.extension;


import vshaxe.Vshaxe;


class LimeDisplayArgumentsProvider {
	

	private var api:Vshaxe;
	private var arguments:String;
	private var parsedArguments:Array<String>;
	private var updateArgumentsCallback:Array<String>->Void;
	
	
	public var description(default,never):String = "from auto-detected project file or lime.projectFile";


	public function new (api:Vshaxe) {

		this.api = api;

	}
	
	
	public function activate (provideArguments:Array<String>->Void):Void {
		
		updateArgumentsCallback = provideArguments;
		
		if (arguments != null) {
			
			update (arguments);
			
		}
		
	}
	
	
	public function deactivate ():Void {
		
		updateArgumentsCallback = null;
		
	}
	
	
	public function update (arguments:String):Void {
		
		if (this.arguments != arguments && api != null) {
			
			this.arguments = arguments;
			this.parsedArguments = api.parseHxmlToArguments(arguments);

			updateArguments();
			
		}
		
	}


	private function updateArguments() {

		if (updateArgumentsCallback != null) {
			
			updateArgumentsCallback (parsedArguments);
			
		}

	}
	
	
}