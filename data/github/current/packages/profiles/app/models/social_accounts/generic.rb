# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Generic < SocialAccount
    sig { override.returns(String) }
    def self.key
      "generic"
    end

    sig { override.returns(String) }
    def self.title
      "Social account"
    end

    sig { override.returns(String) }
    def self.option
      "Other"
    end

    sig { override.returns(Symbol) }
    def self.octicon_name
      :link
    end

    sig { override.returns(T::Boolean) }
    def self.generic?
      true
    end

    sig { override.params(defer_expensive: T::Boolean).returns(RecognitionResult) }
    def recognize(defer_expensive:)
      candidates = self.class.all_providers.filter_map do |provider|
        next if provider.generic?
        candidate_account = provider.new(url:)
        candidate_account if candidate_account.valid?
      end
      nodeinfo_candidates, direct_candidates = candidates.partition(&:needs_nodeinfo_recognition?)

      if direct_candidates.any?
        return RecognitionResult.new(account: T.must(direct_candidates.first))
      end

      if GitHub.nodeinfo_probe_enabled? && nodeinfo_candidates.any?
        host = url_host
        return RecognitionResult.new(account: self, deferred: false) unless host

        result = SocialAccounts::NodeinfoProbe.call(
          host: host,
          cached_only: defer_expensive,
          defer_cache_write: true,
        )
        if result.success?
          matching_candidate = nodeinfo_candidates.find do |account|
            account.nodeinfo_software == result.software_name
          end
          return RecognitionResult.new(
            account: matching_candidate || self,
            nodeinfo_probe_result: result,
          )
        end

        # Probe failed. Return ourselves as-is and report whether or not we've already tried the expensive (network)
        # probe. If we haven't, the caller may wish to schedule a background job to try again.
        #
        # Pass any deferred writes from the probe result through to the caller so they can be throttled gracefully.
        return RecognitionResult.new(
          account: self,
          deferred: defer_expensive,
          nodeinfo_probe_result: result,
        )
      end

      # The URL doesn't match any server-side recognition patterns at all, and there were no candidate providers that
      # require nodeinfo probing to reliably detect, so we really are generic.
      RecognitionResult.new(account: self)
    end

    sig { override.returns(T::Boolean) }
    def valid?
      parsed_uri = URI(url)
      !!(parsed_uri.scheme.in?(%w[http https]) &&
        parsed_uri.host&.include?(".") &&
        parsed_uri.user.nil? &&
        parsed_uri.password.nil?)
    rescue URI::Error
      false
    end
  end
end
