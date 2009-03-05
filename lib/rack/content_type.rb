require 'rack/utils'

module Rack

  # Sets the Content-Type header on responses which don't have one
  class ContentType
    CONTENT_TYPE = "content-type".freeze

    def initialize(app, content_type = "text/html")
      @app, @content_type = app, content_type
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers ||= {}
      headers['Content-Type'] = @content_type unless
        headers.find { |k,v| k.downcase == CONTENT_TYPE }

      [status, headers, body]
    end
  end
end
