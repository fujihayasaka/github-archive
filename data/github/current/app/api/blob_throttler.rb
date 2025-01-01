# typed: true
# frozen_string_literal: true
# Public: Api::BlobThrottler handles rate limit rules specific to blob endpionts.
module Api
  class BlobThrottler < Api::Throttler
    def initialize(path, referer, options = {})
      referer = referer.to_s
        .sub(/^https?:\/\//, "")
        .sub(/\/.*$/, "")

      key = Digest::SHA256.hexdigest("blob:#{path}:#{referer}")

      options = options.reverse_merge({
        max_tries: 100,
        ttl: 5.minutes,
        actor: nil,
      })

      super(key, options)
    end
  end
end
