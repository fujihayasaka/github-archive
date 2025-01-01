# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    module DownloadHelpers
      include Kernel

      RETRYABLE_ERRORS = [
        Net::ReadTimeout,
        Errno::ECONNRESET,
        Errno::EPIPE,
        Errno::ETIMEDOUT,
        Net::OpenTimeout,
        SocketError,
        OpenSSL::SSL::SSLError
      ].freeze

      def save_from_url_without_retry(url:, to:, ttl: 3)
        res = Net::HTTP.get_response(URI(url)) do |res|
          if res.is_a?(Net::HTTPSuccess)
            File.open(to, "wb") do |f|
              res.read_body do |chunk|
                f.write chunk
              end
            end
          end
        end

        case res
        when Net::HTTPSuccess
          [true, res.code]

        when Net::HTTPRedirection
          if ttl > 0
            save_from_url url: res["Location"], to: to, ttl: ttl - 1
          else
            [false, res.code]
          end

        else
          [false, res.code]
        end
      end

      def save_from_url(url:, to:, ttl: 3, timeout_retries: 5)
        attempt = 1

        begin
          save_from_url_without_retry(url: url, to: to, ttl: ttl)
        rescue *RETRYABLE_ERRORS => exception
          attempt += 1
          return [false, "503"] if attempt > timeout_retries

          sleep(attempt**3)
          retry
        end
      end
    end
  end
end
