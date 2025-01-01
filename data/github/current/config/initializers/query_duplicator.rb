# typed: false
# frozen_string_literal: true

require "concurrent"
require "net_http_unix"
require "socket"
require "uri"
require "net/http"

module QueryDuplicator
  class Duplicator
    def initialize(socket_path, api_path, dogstats, logger = GitHub.logger)
      # if the socket_path starts with "http" then we are using a http client
      # otherwise we are using a unix socket and we need to prepend "unix://" to the path
      if socket_path.start_with?("http")
        uri = URI(socket_path)
        @client = Net::HTTP.new(uri.host, uri.port)
      else
        @client = NetX::HTTPUnix.new("unix://#{socket_path}")
      end
      @api_path = api_path
      @dogstats = dogstats
      @logger = logger
    end

    def send(event)
      request = Net::HTTP::Post.new(@api_path)
      request.body = { sql: event.payload[:sql].squeeze(" ").gsub("\n", " ") }.to_json

      retry_count = 0
      begin
        @client.request(request)
        @dogstats.increment("query_analyzer_agent.query_duplicated", tags: ["transition_id:#{ENV["TRANSITION_ID"]}"])
      rescue Errno::ECONNREFUSED, Errno::ENOENT, Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, SocketError, Net::ReadTimeout, Net::OpenTimeout, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
        metric = Duplicator.metric_for_exception(e)
        @dogstats.increment(metric.name, tags: metric.tags)
        retry_count += 1
        if retry_count <= 3
          retry
        else
          @logger.error({
            exception: e,
            msg: "QueryDuplicator::Duplicator.send() failed after 3 retries",
            transition_id: ENV["TRANSITION_ID"]
          })
        end
      end
    end

    # for a given exception return an object with .name and .tags attributes for emission to datadog
    def self.metric_for_exception(exception)
      metric = Struct.new(:name, :tags)
      case exception
      when Errno::ENOENT
        metric.new(name: "query_analyzer_agent.unix_socket_not_found", tags: ["errno:ENOENT"])
      when Errno::ECONNREFUSED
        metric.new(name: "query_analyzer_agent.unix_socket_error", tags: ["errno:ECONNREFUSED"])
      else
        metric.new(name: "query_analyzer_agent.unix_socket_error", tags: ["errno:#{exception.class.to_s.split("::").last}"])
      end
    end
  end

  class Initializer
    def self.running_transition?
      transition_is_present = (ENV.has_key?("TRANSITION_ID") && ENV["TRANSITION_ID"].length > 0)
      force_subscription = ENV.has_key?("QUERY_ANALYZER_SUB")
      transition_is_present || force_subscription
    end

    def self.initialize_subscription
      ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
        socket_path = "/var/run/query-analyzer/agent.sock"
        transition_id = ENV["TRANSITION_ID"]
        if transition_id != nil && transition_id.length > 0
          path = "/agent/v1/query/#{transition_id}"
          event = ActiveSupport::Notifications::Event.new(*args)
          Concurrent::Future.execute do
            # if the GHES_QUERY_DUPLICATOR_ENDPOINT environment variable is set then override the default socket path
            # an example value for this environment variable is "http://localhost:3000" if we want an http client
            query_duplicator_endpoint = ENV["GHES_QUERY_DUPLICATOR_ENDPOINT"] || socket_path
            QueryDuplicator::Duplicator.new(query_duplicator_endpoint, path, GitHub.dogstats).send(event)
          end
        end
      end
    end
  end
end

# Install the hook conditionally
if QueryDuplicator::Initializer.running_transition?
  GitHub.dogstats.increment("query_analyzer_agent.initializer_running", tags: ["transition_id:#{ENV["TRANSITION_ID"]}"])
  QueryDuplicator::Initializer.initialize_subscription
end
