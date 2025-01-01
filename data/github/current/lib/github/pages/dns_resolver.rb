# typed: false
# frozen_string_literal: true

require "timeout"

module GitHub
  module Pages
    # Internal: Provides DNS resolution logic for GitHub Pages.
    # Currently leverages the dnsruby gem to do this.
    class DnsResolver
      class TokenNotFoundError < StandardError; end
      class MissingChallengeKeyError < StandardError; end
      class DnsRequestError < StandardError; end

      # Timeout for the DNS query in seconds
      DNS_RESOLUTION_TIMEOUT = 30

      # Intiantiate a DnsResolver.
      #
      # recursor - Dnsruby::Recursor object which recursively queries DNS servers from the root servers
      # (https://www.iana.org/domains/root/servers) (with DNSSEC validation) by default.
      # logger - GitHub logger
      #
      def initialize(recursor: Dnsruby::Recursor.new, logger: GitHub.logger, dns_resolution_timeout: DNS_RESOLUTION_TIMEOUT)
        @recursor = recursor
        @logger = logger
        @dns_resolution_timeout = dns_resolution_timeout
      end

      # Internal: Verifies ownership of a domain by querying DNS
      #
      # challenge_key - The challenge key to query for.
      # expected_token - The expected token to find in the DNS response.
      def verify_challenge(challenge_key:, expected_token:)
        result = Failure.new(error: StandardError.new(:unprocessed))

        logger.with_named_tags(
          "gh.catalog_service" => "github/pages",
          "code.function" => "verify_challenge",
          "code.namespace" => "github/pages/dns_resolver",
          "gh.pages.challenge.key" => challenge_key) do
          response = query(challenge_key)
          result = verify_response(response, expected_token)
        rescue => e # rubocop:todo Lint/GenericRescue
          result = Failure.new(error: e)
        ensure
          result.tap(&:log)
        end
      end

      private

      attr_reader :logger

      def verify_response(response, expected_token)
        return response unless response.success?

        if challenge_token_present?(response.value!, expected_token)
          Success.new(value: true)
        else
          Failure.new(error: TokenNotFoundError.new)
        end
      end

      def challenge_token_present?(response, expected_token)
        response.answer.any? do |answer|
          found_token = answer.strings.first || ""
          SecurityUtils.secure_compare(found_token, expected_token)
        end
      end

      def query(challenge_key)
        begin
          Timeout.timeout(@dns_resolution_timeout) do
            Success.new(value: @recursor.query(challenge_key, "TXT", "IN", true))
          end
        rescue Timeout::Error
          Failure.new(error: DnsRequestError.new("DNS request timed out"))
        rescue Dnsruby::NXDomain => e
          Failure.new(error: MissingChallengeKeyError.new(e.message))
        rescue => e # rubocop:todo Lint/GenericRescue
          Failure.new(error: DnsRequestError.new(e.message))
        end
      end
    end

    # Internal: A very simple version of a Result type in the spirit of dry-monads. It is intended to wrap logic
    # that would typically require error handling in the form of exceptions. This currently is only being used by the
    # DnsResolver class but may be used more widely (or removed altogether) after the team evaluates further. If used
    # more, we should pull these classes out into separate files.
    class Result
      def success?
        raise NotImplementedError
      end

      def value!
        raise NotImplementedError
      end

      def error!
        raise NotImplementedError
      end
    end

    # Internal: Indicates a successful result.
    class Success < Result
      class UnwrapOnSuccessError < StandardError; end

      def initialize(value:)
        @value = value
      end

      def success?
        true
      end

      def value!
        @value
      end

      def error!
        raise UnwrapOnSuccessError
      end

      def log(logger: GitHub::Logger)
        logger.info(
          "gh.catalog_service" => "github/pages",
          "code.function" => "log",
          "code.namespace" => "github/pages/dns_resolver.success",
          "gh.pages.dns.resolver.success" => true,
          "gh.pages.dns.resolver.value" => @value)
      end
    end

    # Internal: Indicates a failed result.
    class Failure < Result
      class UnwrapOnFailureError < StandardError; end

      def initialize(error:)
        @error = error
      end

      def success?
        false
      end

      def value!
        raise UnwrapOnFailureError
      end

      def error!
        @error
      end

      def log(logger: GitHub::Logger)
        logger.info(
          "gh.catalog_service" => "github/pages",
          "code.function" => "log",
          "code.namespace" => "github/pages/dns_resolver.failure",
          "gh.pages.dns.resolver.success" => false,
          "gh.pages.dns.resolver.value" => @error)
      end
    end
  end
end
