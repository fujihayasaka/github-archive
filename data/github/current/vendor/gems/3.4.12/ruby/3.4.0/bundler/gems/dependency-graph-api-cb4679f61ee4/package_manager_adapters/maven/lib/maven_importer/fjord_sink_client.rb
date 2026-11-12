require "net/http"
require "json"
require "uri"
require_relative "../logging"

module Maven
  class FjordSinkClient
    include Logging

    class FjordCheckpoint
      NAME = "maven-%s-max-id"

      def initialize(url, index)
        @url = url
        @index = index
      end

      def set(id)
        point = sprintf(NAME, @index)
        request = Net::HTTP::Put.new("/checkpoints/#{point}")
        request.set_form_data("value" => id)
        http.request(request)
      end

      def value
        point = sprintf(NAME, @index)
        request = Net::HTTP::Get.new("/checkpoints/#{point}")
        response = http.request(request)
        JSON.parse(response.body)["value"]
      end

      private
      def http
        uri = URI(@url)
        conn = Net::HTTP.new(uri.host, uri.port)
        conn.use_ssl = (uri.scheme == "https")
        conn
      end
    end

    def initialize(url, checkpoint_url, flush_interval: 100)
      @url = url
      @checkpoint_url = checkpoint_url
      @report_size = flush_interval
      @package_releases = []
    end

    def checkpoint(index_name)
      FjordCheckpoint.new(@checkpoint_url, index_name)
    end

    def <<(package_release)
      @package_releases << package_release
      flush if @package_releases.count >= @report_size
    end

    def flush
      payload = {}
      payload["events"] = @package_releases.map { |release| release.fjord_hash }

      uri = URI("#{@url}/api/v1/events")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      request = Net::HTTP::Post.new(uri.request_uri)

      request["Content-Type"] = "application/json"
      request["ClientID"] = "dependency-graph-maven"
      request.body = payload.to_json

      response = http.request(request)

      logger.info "[FJORD] Flushed #{@package_releases.count} package releases to sink"
      @package_releases = []
    end
  end

end
