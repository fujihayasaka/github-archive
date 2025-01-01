# typed: true
# frozen_string_literal: true

module AssetUploadable
  class Cdn
    class Error < StandardError
    end

    def self.purge(*keys)
      keys.compact!
      keys.uniq!
      keys.sort!
      return if keys.blank?
      return unless http = faraday

      start = Time.now
      res = http.post GitHub.alambic_cdn_purge_path do |req|
        req.params[:key] = keys * ","
      end

      ms = (Time.now - start) * 1_000

      if res.status != 200
        send_stats(keys, ms, success: false)
        raise Error, "Unsuccessful response: #{res.status}"
      end

      send_stats(keys, ms, success: true)
    end

    def self.send_stats(keys, ms, success:)
      tags = success ? %w(result:success) : %w(result:error)
      GitHub.dogstats.histogram("cdn.purged_keys", keys.size, tags: tags)
      GitHub.dogstats.timing("cdn.purges", ms, tags: tags)
    end
    private_class_method :send_stats

    def self.faraday
      return @faraday if defined?(@faraday) && @faraday

      @faraday = nil
      return unless token = GitHub.alambic_cdn_token
      return unless url = GitHub.alambic_cdn_url
      @faraday = Faraday.new(url: url) do |faraday|
        faraday.adapter Faraday.default_adapter
      end
      @faraday.headers["Authorization"] = "Token #{token}"
      @faraday
    end
    private_class_method :faraday
  end
end
