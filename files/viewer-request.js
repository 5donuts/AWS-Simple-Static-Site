// See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/example-function-add-index.html
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // Check if the URI has no filename, in which case, add 'index.html'.
  if (uri.endsWith('/')) {
    request.uri += 'index.html';
  }
  // Check if the URI is missing a file extension (e.g., the request is for a
  // page but doesn't include the trailing '/'), in which case add '/index.html'.
  else if (!uri.includes('.')) {
    request.uri += '/index.html';
  }

  return request;
}
