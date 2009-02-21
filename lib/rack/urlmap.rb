module Rack
  # Rack::URLMap takes a hash mapping urls or paths to apps, and
  # dispatches accordingly.  Support for HTTP/1.1 host names exists if
  # the URLs start with <tt>http://</tt> or <tt>https://</tt>.
  #
  # If two arguments are passed, the first is the default app in the chain,
  # and the second is the hash mapping urls to apps. In this case, if the
  # url doesn't match anything in the hash, the request is passed to the
  # default app instead.
  #
  # URLMap modifies the SCRIPT_NAME and PATH_INFO such that the part
  # relevant for dispatch is in the SCRIPT_NAME, and the rest in the
  # PATH_INFO.  This should be taken care of when you need to
  # reconstruct the URL in order to create links.
  #
  # URLMap dispatches in such a way that the longest paths are tried
  # first, since they are most specific.

  class URLMap
    def initialize(map_or_app, map=nil)
      if map
        @default = map_or_app
      else
        map = map_or_app
        @default = lambda { |env|
          [404, {"Content-Type" => "text/plain"}, ["Not Found: #{env["PATH_INFO"].to_s.squeeze("/")}"]]
        }
      end
      @mapping = map.map { |location, app|
        if location =~ %r{\Ahttps?://(.*?)(/.*)}
          host, location = $1, $2
        else
          host = nil
        end

        unless location[0] == ?/
          raise ArgumentError, "paths need to start with /"
        end
        location = location.chomp('/')

        [host, location, app]
      }.sort_by { |(h, l, a)| [-l.size, h.to_s.size] }  # Longest path first
    end

    def call(env)
      path = env["PATH_INFO"].to_s.squeeze("/")
      script_name = env['SCRIPT_NAME']
      hHost, sName, sPort = env.values_at('HTTP_HOST','SERVER_NAME','SERVER_PORT')
      @mapping.each { |host, location, app|
        next unless (hHost == host || sName == host \
          || (host.nil? && (hHost == sName || hHost == sName+':'+sPort)))
        next unless location == path[0, location.size]
        next unless path[location.size] == nil || path[location.size] == ?/

        return app.call(
          env.merge(
            'SCRIPT_NAME' => (script_name + location),
            'PATH_INFO'   => path[location.size..-1]))
      }
      @default.call(env)
    end
  end
end

