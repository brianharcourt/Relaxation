component
	accessors="true"
	displayname="Chill REST Framework"
	hint="I am the Chill. Framework for REST in CF. Relax, I got this!"
	output="false"
{

	property name="BeanFactory" type="component";
	property name="cfmlFunctions" type="component";
	property name="AuthorizationMethod" type="any";
	property name="OnErrorMethod" type="any";
	
	variables.Config = {};
	
	/**
	* @hint "I initialize the object and get the routing all setup."
	* @output false
	**/
	public component function init( required any Config ) {
		/* Set object to handle CFML stuff. */
		setcfmlFunctions( new cfmlFunctions() );
		/* Deal with different types of configs passed in. */
		arguments.Config = translateConfig( arguments.Config );
		/* Set the Return Format. Default JSON. */
		variables.Config.ReturnFormat = isDefined("arguments.Config.ReturnFormat") ? arguments.Config.ReturnFormat : 'JSON';
		/* Get the pattern matching for resources setup. */
		configureResources( arguments.Config.RequestPatterns );
		/* Always return the object. */
		return this;
	}
	
	/**
	* @hint "I return the configuration structure."
	* @output false
	**/
	public struct function getConfig() {
		return variables.Config;
	}
	
	/**
	* @hint "I will handle a REST request. Given the requested path and verb, I will call the correct resource and method."
	* @output false
	**/
	public struct function handleRequest(
		string Path = CGI.PATH_INFO,
		string Verb = CGI.REQUEST_METHOD,
		string RequestBody,
		struct URLScope,
		struct FormScope
	) {
		/* Try to get reasonable defauls set. */
		if ( isNull(arguments.URLScope) && isDefined("URL") && isStruct(URL) ) {
			arguments.URLScope = URL;
		}
		if ( isNull(arguments.FormScope) && isDefined("FORM") && isStruct(FORM) ) {
			arguments.FormScope = FORM;
		}
		if ( isNull(arguments.RequestBody) && isJSON(trim(ToString(GetHttpRequestData().Content))) ) {
			arguments.RequestBody = trim(ToString(GetHttpRequestData().Content));
		}
		var result = {
			"Success" = true
			,"Output" = ""
			,"Error" = ""
			,"ErrorMessage" = ""
		};
		var resource = findResourceConfig( argumentCollection = arguments );
		if ( !resource.Located ) {
			/* We could not locate the configuration for handling this type of request. */
			result.Success = false;
			result.Error = resource.Error;
			if ( resource.Error == "ResourceNotFound" ) {
				result.ErrorMessage = "A resource to handle the pattern (#arguments.Path#) could not be found.";
			} else if ( resource.Error == "VerbNotFound" ) {
				result.ErrorMessage = "The resource (#arguments.Path#) is not configured to handle (#arguments.Verb#) requests.";
			}
			return result;
		}
		if ( !isNull(getAuthorizationMethod()) ) {
			var authorize = getAuthorizationMethod();
			if ( !authorize(resource) ) {
				result.Success = false;
				result.Error = "NotAuthorized";
			}
		}
		var bean = getBeanFactory().getBean(resource.Bean);
		/* Gather the arguments needed to call the method. */
		var args = gatherRequestArguments( argumentCollection = arguments, ResourceMatch = resource);
		/* Now call the method on the bean! */
		try {
			var methodResult = variables.cfmlFunctions.cfmlInvoke(bean, resource.Method, args);
			/* If calling the method was successful. Tell the client we are sending JSON. */
			getpagecontext().getresponse().setcontenttype('application/json');
		} catch (Any e) {
			if ( !isNull(getOnErrorMethod()) ) {
				var onError = getOnErrorMethod();
				onError(e, resource, args);
			} else {
				rethrow;
			}
		}
		result.Output = isDefined("methodResult") ? SerializeJSON(methodResult) : "";
		return result;
	}
	
	
	/*
	 * PRIVATE UTILITY FUNCTIONS
	 **/
	
	
	/**
	* @hint "I will configure the pattern matching for the different resources."
	* @output false
	**/
	private void function configureResources( required struct Patterns ) {
		variables.Config.Resources = [];
		/* By sorting the keys this way, static patterns should take priority over dynamic ones. */
		var keyList = ListSort(StructKeyList(arguments.Patterns), 'textnocase', 'asc');
		for ( var key in ListToArray(keyList) ) {
			var resource = arguments.Patterns[key];
			var resource["Pattern"] = key & ( Right(trim(key),1) EQ '/' ? '' : '/' );
			/* Start building the regex for this pattern. */
			resource.Regex = key;
			/* Add trailing slash to make matching easier. */
			resource.Regex &= ( Right(trim(resource.Regex),1) EQ '/' ? '' : '/' );
			/* Replace the {} sections with capture groups. */
			resource.Regex = REReplace(resource.Regex, "{[^}]*?}", "([^/]+?)", "all");
			/* Make sure it matches exactly. (Start to finish) */
			resource.Regex = '^' & resource.Regex & '$';
			/* Add resources with arguments in the path to the bottom. */
			ArrayAppend(
				variables.Config.Resources
				,resource
			);
		}
	}
	
	/**
	* @hint "Give an resource path and verb, I will return the config object."
	* @output false
	**/
	private struct function findResourceConfig( required string Path, required string Verb ) {
		/* Add trailing slash to make matching easier. */
		arguments.Path &= ( Right(trim(arguments.Path),1) EQ '/' ? '' : '/' );
		var result = {
			"Located" = false
			,"Error" = ""
			,"Path" = ""
			,"Pattern" = ""
			,"Regex" = ""
			,"Verb" = ""
		};
		for ( var resource in variables.Config.Resources ) {
			if ( RefindNoCase(resource.Regex,arguments.Path) ) {
				var match = resource;
				break;
			}
		}
		if ( IsNull(match) ) {
			result.Error = "ResourceNotFound";
		} else {
			if ( !StructKeyExists(match, arguments.Verb) ) {
				result.Error = "VerbNotFound";
			} else {
				result.Located = true;
				result.Path = arguments.Path;
				result.Pattern = match.Pattern;
				result.Regex = match.Regex;
				result.Verb = arguments.Verb;
				StructAppend(result, match[arguments.Verb]);
			}
		}
		return result;
	}
	
	/**
	* @hint "I will gather all the request arguments up from the possible sources. (URL, Form, URI, Request Body)"
	* @output false
	**/
	private struct function gatherRequestArguments( required struct ResourceMatch, string RequestBody = "", struct URLScope = {}, struct FormScope = {} ) {
		/* Grab the DefaultArguments if they exist. */
		var DefaultArgs = isNull(arguments.ResourceMatch.DefaultArguments) ? {} : arguments.ResourceMatch.DefaultArguments;
		/* Get the arguments from the URIs (e.g. /product/321 to ProductID=321) */
		var PathValues = {};
		if ( ReFindNoCase("[{}]", ResourceMatch.Pattern) ) {
			var nameLenPos = RefindNoCase(ResourceMatch.Regex, ResourceMatch.Pattern, 1, true);
			var valueLenPos = RefindNoCase(ResourceMatch.Regex, ResourceMatch.Path, 1, true);
			if ( ArrayLen(nameLenPos.Len) == ArrayLen(valueLenPos.Len) && ArrayLen(valueLenPos.Len) > 1 ) {
				for ( var i = 2; i <= ArrayLen(nameLenPos.Len); i++ ) {
					var argName = ReReplaceNoCase(mid(ResourceMatch.Pattern, nameLenPos.Pos[i], nameLenPos.Len[i]), "[{}]", "", "all");
					PathValues[argName] = mid(ResourceMatch.Path, valueLenPos.Pos[i], valueLenPos.Len[i]);
				}
			}
		}
		/* Get the value of the Body. */
		var Payload = {};	
		if ( len(trim(arguments.RequestBody)) && isJSON(trim(arguments.RequestBody)) ) {
			/* The request body can be an array or something else that will not StructAppend. So, they are added to the args as "Payload". */
			Payload = DeserializeJSON(trim(arguments.RequestBody));
		}
		var args = {
			"Payload" = Payload,
			"ArgumentSources" = {
				"DefaultArguments" = DefaultArgs,
				"FormScope" = arguments.FormScope,
				"PathValues" = PathValues,
				"Payload" = Payload,
				"URLScope" = arguments.URLScope
			}
		};
		/* Coalesce all the sources together. User "overwrite" false and put the highest priority first.  */
		StructAppend(args, PathValues, false);	/* Path 1st */
		if ( isStruct(Payload) ) {
			StructAppend(args, Payload, false);	/* Body 2nd */
		}
		StructAppend(args, URLScope, false);	/* URL 3rd */
		StructAppend(args, FormScope, false);	/* Form 4th */
		StructAppend(args, DefaultArgs, false);	/* DefaultArguments 5th */
		return args;
	}
	
	/**
	* @hint "I will handle any type of config passed in."
	* @output false
	**/
	private struct function translateConfig( required any Config ) {
		/* Deal with different types of configs passed in. */
		
		if ( isStruct(arguments.Config) ) {
			/* It's already a struct. Return it. */
			return arguments.Config;
		}
		
		if ( isJSON(trim(arguments.Config)) ) {
			/* It's a JSON string. Deserialize and return it. */
			return DeserializeJSON(trim(arguments.Config));
		}
		
		if ( !fileExists(arguments.Config) && fileExists(expandPath(arguments.Config)) ) {
			arguments.Config = expandPath(arguments.Config);
		}
		if ( !fileExists(arguments.Config) ) {
			/* Throw error */
			throw( type="Relaxation.Config.InvalidPath", message="I could not find a file at the path you supplied. [#arguments.Config#]");
		}
		return DeserializeJSON(trim(fileRead(arguments.Config)));
	}

}