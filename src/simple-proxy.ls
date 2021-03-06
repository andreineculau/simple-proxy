url    = require \url
http   = require \http
https  = require \https
events = require \events


exports.proxyPass = (proxyURI, options={}) ->
  p = new Proxy(proxyURI, options)
  return p.server.bind(p)


class exports.Proxy extends events.EventEmitter
  (proxyURI, options = {}) ->
    @logging            = options.logging                 ? false
    @timeout            = options.timeout                 ? 0
    @agent              = options.agent                   ? void
    @preserveHost       = options.preserveHost            ? false
    @rejectUnauthorized = options.rejectUnauthorized      ? true

    @{protocol, hostname, port, pathname} = url.parse(proxyURI)

    # We concatenate with req.url later; no trailing slash is desired:
    @pathname .= replace /\/$/, ''

    if @protocol == 'https:'
      @requestLib = https
      @port or= 443
    else if @protocol == 'http:'
      @requestLib = http
      @port or= 80
    else
      throw new Error "Unsupported protocol: #{@protocol}"


  server: (req, res, next) ->
    options =
      host               : @hostname
      path               : @pathname + req.url
      port               : @port
      method             : req.method
      headers            : req.headers
      agent              : @agent
      rejectUnauthorized : @rejectUnauthorized

    options.headers.host = @hostname  unless @preserveHost

    proxyRequest = @requestLib.request options, (proxyResponse) ~>
      @onProxyResponse proxyResponse, res, options

    if @timeout
      proxyRequest.setTimeout @timeout, (error) ~>
        error = "Request timed out after #{@timeout} ms."
        @emit \proxyTimeout, error, options
        @onProxyTimeout error, options, res
        proxyRequest.abort!
        return

    proxyRequest.on \error, (error) ~>
      @emit \proxyError, error, options
      @onProxyError error, options, res

    if req.headers['content-length']
      @processRequestData proxyRequest, req, options
    else
      proxyRequest.end!


  processRequestData: !(proxyRequest, req, options) ->
    requestData = ''

    req.on \data, (chunk) ~>
      requestData += chunk
      proxyRequest.write chunk, \binary

    req.on \end, ~>
      @emit \requestEnd, requestData, options
      proxyRequest.end!


  onProxyResponse: !(proxyResponse, res, options) ->
    res.writeHead proxyResponse.statusCode, proxyResponse.headers
    responseData = ''

    proxyResponse.on \data, (chunk) ->
      responseData += chunk
      res.write chunk, \binary

    proxyResponse.on \end, ~>
      console.error "Proxy end: #responseData"  if @logging
      @emit \proxyResponse, responseData, options
      res.end!


  onProxyTimeout: !(err, options, res) ~>
    console.error "Proxy timeout: #err"  if @logging
    res.writeHead 504, 'Gateway Timeout'
    res.end!


  onProxyError: !(err, options, res) ~>
    console.error "Proxy error: #err, #{JSON.stringify(options)}"  if @logging
    res.writeHead 502, 'Bad Gateway'
    res.end!
