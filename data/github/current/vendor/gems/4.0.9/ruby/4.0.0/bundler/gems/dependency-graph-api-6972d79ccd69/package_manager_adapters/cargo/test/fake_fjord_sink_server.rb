require_relative "../lib/cargo_importer"
require "minitest/autorun"
require "addressable/uri"

## Lovingly copied from Nuget

class FakeFjordSinkServer
  attr_accessor :package_releases, :checkpoints

  def initialize
    @package_releases = []
    @checkpoints = Hash.new(0)
  end

  def url
    "http://" + "#{@serv.addr[2]}:#{@serv.addr[1]}"
  end

  def start
    @serv = TCPServer.new("127.0.0.2", 0)
    @closing = false
    server_thread = Thread.new do
      begin
        while conn = @serv.accept
          m, path, _ = conn.gets.split(" ")
          headers = parse_headers(conn)
          data = conn.read(headers["Content-Length"].to_i)
          ret = handle_request(m, path, Addressable::URI.unescape(data))

          conn.print "HTTP/1.1 200\r\n"
          conn.print "Content-Type: text/html\r\n"
          conn.print "\r\n"
          conn.print ret.to_s
          conn.close
        end
      rescue IOError
        raise unless @closing
      end

    end
    server_thread.abort_on_exception
  end

  def close
    @closing = true
    @serv.close
  end

  private
  def handle_request(method, path, data)
    case path
    when "/api/v1/events"
      JSON.parse(data)["events"].each do |event|
        if event["schema"] == Cargo::PACKAGES_SCHEMA
          @package_releases << event
        end
      end
      nil
    when /^\/checkpoints\/(.*)$/
      if method == "PUT"
        @checkpoints[$1] = Integer(data.gsub("value=", ""))
      end
      { value: @checkpoints[$1] }.to_json
    else
      nil
    end
  end

  def parse_headers(request)
    headers = {}
    while line = request.gets.split(" ", 2)
      break if line[0] == ""
      headers[line[0].chop] = line[1].strip
    end
    headers
  end
end

# Dont show logs in tests
module Logging
  def logger
    # Even if we don't use scrolls in the tests, they rely on an initialized instance for setting the context.
    @scrolls_init = Scrolls.init(global_context: { "gh.dependency_graph.package_manager" => "rust" }, timestamp: true)
    @logger ||= Logger.new("/dev/null")
  end
end
