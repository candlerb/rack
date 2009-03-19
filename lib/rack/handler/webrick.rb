require 'webrick'
require 'stringio'
require 'rack/content_length'

module Rack
  module Handler
    class WEBrick < ::WEBrick::HTTPServlet::AbstractServlet
      def self.run(app, options={})
        server = ::WEBrick::HTTPServer.new(options)
        server.mount "/", Rack::Handler::WEBrick, app
        trap(:INT) { server.shutdown }
        yield server  if block_given?
        server.start
      end

      def initialize(server, app)
        super server
        @app = Rack::ContentLength.new(app)
      end

      def service(req, res)
        env = req.meta_vars
        env.delete_if { |k, v| v.nil? }

        env.update({"rack.version" => [0,1],
                     "rack.input" => StringIO.new(req.body.to_s),
                     "rack.errors" => $stderr,

                     "rack.multithread" => true,
                     "rack.multiprocess" => false,
                     "rack.run_once" => false,

                     "rack.url_scheme" => ["yes", "on", "1"].include?(ENV["HTTPS"]) ? "https" : "http"
                   })

        env["HTTP_VERSION"] ||= env["SERVER_PROTOCOL"]
        env["QUERY_STRING"] ||= ""
        env["REQUEST_PATH"] ||= "/"
        if env["PATH_INFO"] == ""
          env.delete "PATH_INFO"
        else
          path, n = req.request_uri.path, env["SCRIPT_NAME"].length
          env["PATH_INFO"] = path[n, path.length-n]
        end

        status, headers, body = @app.call(env)
        begin
          res.status = status.to_i
          res.chunked = true
          headers.each { |k, vs|
            res.chunked = false if k.downcase == "content-length"
            if k.downcase == "set-cookie"
              res.cookies.concat vs.split("\n")
            else
              vs.split("\n").each { |v|
                res[k] = v
              }
            end
          }
          res.body = lambda { |out|
            body.each { |part|
              out << part
            }
          }
        ensure
          body.close  if body.respond_to? :close
        end
      end
    end
  end
end

# Selected WEBrick monkey patches to allow streaming, taken from
# http://redmine.ruby-lang.org/issues/show/855

unless WEBrick::HTTPResponse.instance_methods.include?("send_body_proc") ||
       WEBrick::HTTPResponse.instance_methods.include?(:send_body_proc)
module WEBrick
  class HTTPResponse
    def send_body(socket)
      if @body.respond_to?(:read) then send_body_io(socket)
      elsif @body.respond_to?(:call) then send_body_proc(socket)
      else send_body_string(socket)
      end
    end

    # If the response body is a proc, then we invoke it and pass in
    # an object which supports "write" and "<<" methods. This allows
    # arbitary output streaming.
    def send_body_proc(socket)
      if @request_method == "HEAD"
        # do nothing
      elsif chunked?
        @body.call(ChunkedWrapper.new(socket, self))
        _write_data(socket, "0#{CRLF}#{CRLF}")
      else
        size = @header['content-length'].to_i
        @body.call(socket)   # TODO: StreamWrapper which supports offset, size
        @sent_size = size
      end
    end
          
    class ChunkedWrapper
      def initialize(socket, resp)
        @socket = socket
        @resp = resp
      end
      def write(buf)
        return if buf.empty?
        size = ::Rack::Utils.bytesize(buf)
        data = ""
        data << format("%x", size) << CRLF
        data << buf << CRLF
        socket = @socket
        @resp.instance_eval {
          _write_data(socket, data)
          @sent_size += size
        }
      end
      alias :<< :write
    end

    # There is a problem buried deep inside WEBrick::HTTPResponse#setup_header
    # which prevents streaming of Proc bodies without a Content-Length to
    # HTTP/1.0 clients. It says there:
    #   unless @body.is_a?(IO)
    #     @header['content-length'] = @body ? @body.size : 0
    #   end
    # Rather than replace the whole of setup_header, I have ignored this problem
    # on the basis that there aren't many HTTP/1.0 clients around these days.
  end
end
end

if defined?(WEBrick::HTTPResponse::BUFSIZE) && WEBrick::HTTPResponse::BUFSIZE < 16384
  old_verbose, $VERBOSE = $VERBOSE, nil
  # Increase from default of 4K for efficiency, similar to
  # http://svn.ruby-lang.org/cgi-bin/viewvc.cgi/branches/ruby_1_8/lib/net/protocol.rb?r1=11708&r2=12092
  # In trunk the default is 64K and can be adjusted using :InputBufferSize,
  # :OutputBufferSize
  WEBrick::HTTPRequest::BUFSIZE = 16384
  WEBrick::HTTPResponse::BUFSIZE = 16384
  $VERBOSE = old_verbose
end
