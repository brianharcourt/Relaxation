component
	accessors="true"
	displayname="HTTP request / response utilities"
	hint="I am a collection of methods to help manipulate http requests."
	output="false"
{
	
	/**
	* @hint "I will return a date in the correct format for http headers."
	**/
	public string function formatHTTPDate(required date Date) {
		return DateFormat(arguments.Date,"ddd, dd mmm yyyy") & TimeFormat(arguments.Date,"HH:nn:ss") & ' GMT';
	}
	
	/**
	* @hint "I set response content type."
	* @output false
	**/
	public void function setResponseContentType( required string ContentType ) {
		getpagecontext().getresponse().setContentType(JavaCast("string",arguments.ContentType));
	}
	
	/**
	* @hint "I set response headers."
	* @output false
	**/
	public void function setResponseHeader( required string Header, string HeaderText = "" ) {
		getpagecontext().getResponse().setHeader(JavaCast("string",arguments.Header), JavaCast("string",arguments.HeaderText));
	}
	
	/**
	* @hint "I set response status headers."
	* @output false
	**/
	public void function setResponseStatus( required numeric Status, string StatusText = "" ) {
		getpagecontext().getResponse().setStatus(JavaCast("int",arguments.Status), JavaCast("string",arguments.StatusText));
	}
	
}