# typed: true
# frozen_string_literal: true

class PurgeFastlyUrlJob < ApplicationJob
  queue_as :cdn

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  class FastlyResponseCodeError < StandardError; end

  retry_on_dirty_exit
  retry_on Faraday::Error
  retry_on FastlyResponseCodeError

  # Public: Purges a given fastly url.
  #
  # options - Hash
  #           :url - String url purge.
  #
  # Returns nothing.
  def perform(options = {})
    options = options.with_indifferent_access
    return unless http = self.class.faraday
    res = http.run_request(:purge, options["url"], nil, { "Fastly-Key" => GitHub.fastly_api_token })
    if res.status != 200
      raise FastlyResponseCodeError, "Unsuccessful response: #{res.status}, when using URL #{options["url"]}"
    end
  end

  # Internal: Allows replacing the faraday adapter in a test
  def self.faraday
    return @faraday if defined?(@faraday) && @faraday
    @faraday = Faraday.new { |f| f.adapter(Faraday.default_adapter) }
  end
end
