# typed: true
# frozen_string_literal: true

module TraceRenderer
  class DatadogClient

    def self.get_trace(trace_id)
      # initialize the client
      time_hint = 1.day.ago.to_i * 1000
      uri = URI.parse("https://app.datadoghq.com/api/unstable/ui/trace/#{trace_id}?time_hint=#{time_hint}")
      client = self.client(uri)

      # make our API request
      response = client.request(self.get_request(uri))

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        GitHub.logger.error("TraceRenderer::DatadogClient to fetch data",
          "code.namespace": "TraceRenderer::DatadogClient",
          "code.function": "get_trace",
          trace_id: trace_id,
          time_hint: time_hint,
          response: response,
          error: response.message
        )
        nil
      end
    end

    def self.client(url)
      client = Net::HTTP.new(url.host, url.port)
      client.use_ssl = true
      client
    end

    def self.get_request(uri)
      request = Net::HTTP::Get.new(uri)
      request["Content-Type"] = "application/json"
      request["DD-API-KEY"] = ENV["DATADOG_API_KEY_CHATOPS"]
      request["DD-APPLICATION-KEY"] = ENV["DATADOG_APP_KEY_CHATOPS"]
      request
    end
  end
end
