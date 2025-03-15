// example server we can use to emulate the lambda runtime api for  local
// development
import http from "node:http";

const server = http.createServer((request, response) => {
  console.log(`${request.method} ${request.url}`);
  const body = JSON.stringify({
    some: "payload",
  });
  const contentLength = body.length;

  response.writeHead(200, "OK", {
    "content-length": contentLength,
    "content-type": "application/json",
    "lambda-runtime-aws-request-id": "request-id-from-nodejs",
    "lambda-runtime-trace-id": "some-xray-trace-id",
  });
  response.write(body);
  response.end();
});

console.log("mock runtime api server listening on port 3000");
server.listen(3000);
