# typed: strict
# frozen_string_literal: true

module Alloy
  class SelectiveSsr
    sig { returns(SelectiveSsr::Metadata) }
    attr_reader :metadata

    sig { returns(SelectiveSsr::Hints) }
    attr_reader :hints

    sig { returns(Browser::Base) }
    attr_reader :browser

    DEFAULT_CPU_BUCKET = "unknown" # Indicates that the browser is not supported or that the cookie is not set
    VALID_CPU_BUCKETS = %w[sm md lg xlg].freeze

    sig do
      params(
        request: ActionDispatch::Request,
        ssr_hints: Alloy::SelectiveSsr::Hints,
        disable_ssr: T::Boolean,
        force_ssr: T::Boolean,
        user: T.nilable(User),
        app_name: String,
      ).returns(Alloy::SelectiveSsr)
    end
    def self.build(request:, ssr_hints:, disable_ssr:, force_ssr:, user:, app_name:)
      ssr_override = if force_ssr
        true
      elsif disable_ssr
        false
      else
        nil
      end

      new(
        metadata: Alloy::SelectiveSsr::Metadata.new(
          logged_in: !!user,
          robot: !!GitHub.robot?(request.user_agent.to_s),
          mobile: !!GitHub::Mobile.mobile_user_agent?(request.user_agent.to_s),
          spammy: !!user.try(:spammy?),
          user_agent: request.user_agent.to_s,
          cpu_bucket: determine_cpu_bucket(request),
          override: determine_selective_ssr_override(ssr_override, app_name)
        ),
        hints: ssr_hints,
      )
    end

    sig { params(request: ActionDispatch::Request).returns(String) }
    def self.determine_cpu_bucket(request)
      cookie = request.cookies&.[]("cpu_bucket")

      return DEFAULT_CPU_BUCKET if cookie.blank? || !VALID_CPU_BUCKETS.include?(cookie)

      cookie
    end

    sig { params(ssr_override: T.nilable(T::Boolean), app_name: String).returns(T.nilable(T::Boolean)) }
    def self.determine_selective_ssr_override(ssr_override, app_name)
      return false unless Alloy::Manifest.entry_supports_ssr?(app_name)

      ssr_override
    end

    sig { params(metadata: SelectiveSsr::Metadata, hints: SelectiveSsr::Hints).void }
    def initialize(metadata:, hints:)
      @metadata = metadata
      @hints = hints
      user_agent = metadata.user_agent.slice(0, Browser.user_agent_size_limit - 1)
      @browser = T.let(Browser.new(user_agent), Browser::Base)
      @tier = T.let(nil, T.nilable(Integer))
    end

    sig { returns(Integer) }
    def tier
      return @tier unless @tier.nil?

      @tier = if tier0?
        Tiers::TIER_0
      elsif tier4? # check overrides first
        Tiers::TIER_4
      elsif tier1?
        Tiers::TIER_1
      elsif tier2?
        Tiers::TIER_2
      else
        Tiers::TIER_3
      end
    end

    # Only Tier 4 completely skips Alloy. Other tiers
    # will be served according to Alloy's capacity.
    sig { returns(T::Boolean) }
    def ssr_enabled?
      tier != Tiers::TIER_4
    end

    private

    sig { returns(T::Boolean) }
    def tier0?
      !!metadata.override
    end

    sig { returns(T::Boolean) }
    def tier1?
      bot? || !metadata.logged_in || !!hints.highly_cacheable || !!hints.no_js_experience
    end

    sig { returns(T::Boolean) }
    def tier2?
      mobile? || !major_browser? || !major_os? || low_powered_device?
    end

    sig { returns(T::Boolean) }
    def tier4?
      # we don't want to match override `nil`
      metadata.override == false || metadata.spammy
    end

    sig { returns(T::Boolean) }
    def bot?
      metadata.robot || browser.bot?
    end

    sig { returns(T::Boolean) }
    def mobile?
      metadata.mobile || browser.device.mobile? || browser.device.tablet?
    end

    sig { returns(T::Boolean) }
    def major_browser?
      browser.chromium_based? || browser.safari? || browser.firefox?
    end

    sig { returns(T::Boolean) }
    def major_os?
      platform.windows? || platform.mac? || platform.linux?
    end

    sig { returns(T::Boolean) }
    def low_powered_device?
      metadata.cpu_bucket == "sm" || metadata.cpu_bucket == "md"
    end

    sig { returns(Browser::Platform) }
    def platform
      browser.platform
    end
  end
end
