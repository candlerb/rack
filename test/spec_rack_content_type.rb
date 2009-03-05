require 'test/spec'

require 'rack/mock'
require 'rack/content_type'

context "Rack::ContentType" do
  specify "sets Content-Type to default text/html if none is set" do
    app = lambda { |env| [200, {}, "Hello, World!"] }
    response = Rack::ContentType.new(app).call({})
    response[1]['Content-Type'].should.equal 'text/html'
  end

  specify "sets Content-Type to chosen default if none is set" do
    app = lambda { |env| [200, {}, "Hello, World!"] }
    response = Rack::ContentType.new(app, 'application/octet-stream').call({})
    response[1]['Content-Type'].should.equal 'application/octet-stream'
  end

  specify "does not change Content-Type if it is already set" do
    app = lambda { |env| [200, {'Content-Type' => 'foo/bar'}, "Hello, World!"] }
    response = Rack::ContentType.new(app).call({})
    response[1]['Content-Type'].should.equal 'foo/bar'
  end

  specify "case insensitive detection of Content-Type" do
    app = lambda { |env| [200, {'CONTENT-Type' => 'foo/bar'}, "Hello, World!"] }
    response = Rack::ContentType.new(app).call({})
    response[1].select { |k,v| k.downcase == "content-type" }.should.equal [["CONTENT-Type","foo/bar"]]
  end
end
