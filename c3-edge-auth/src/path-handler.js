function handler(event) {
    var request = event.request;
    
    // Log the request details
    console.log('----------------------------------------');
    console.log('Request URI: ' + request.uri);
    console.log('Request Method: ' + request.method);
    console.log('Request QueryString: ' + JSON.stringify(request.querystring));
    console.log('Request Headers: ' + JSON.stringify(request.headers));
    
    // Allow the request to continue to its original destination
    return request;
}