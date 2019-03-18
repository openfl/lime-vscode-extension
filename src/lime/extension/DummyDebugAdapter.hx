package lime.extension;

import adapter.DebugSession;
import protocol.debug.Types;

class DummyDebugAdapter extends adapter.DebugSession
{
	override function initializeRequest(response:InitializeResponse, args:InitializeRequestArguments)
	{
		trace("init");
		response.body.supportsConfigurationDoneRequest = true;
		response.body.supportsFunctionBreakpoints = false;
		response.body.supportsConditionalBreakpoints = true;
		response.body.supportsEvaluateForHovers = true;
		response.body.supportsStepBack = false;
		response.body.supportsSetVariable = true;
		response.body.exceptionBreakpointFilters = [
			{filter: "all", label: "Stop on all exceptions"}];

		sendResponse(response);
	}

	override function launchRequest(response:LaunchResponse, args:LaunchRequestArguments) {}

	override function setExceptionBreakPointsRequest(response:SetExceptionBreakpointsResponse, args:SetExceptionBreakpointsArguments) {}

	override function attachRequest(response:AttachResponse, args:AttachRequestArguments) {}

	static function main()
	{
		trace("hello");
	}
}
