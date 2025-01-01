# typed: true
# frozen_string_literal: true

module Alloy
  module Tiers
    TIER_0 = 0
    TIER_1 = 1
    TIER_2 = 2
    TIER_3 = 3
    TIER_4 = 4
  end

  class SSRMetadata < T::Struct
    const :logged_in, T::Boolean
    const :robot, T::Boolean
    const :mobile, T::Boolean
    const :spammy, T::Boolean
    const :user_agent, String
    const :cpu_bucket, String
    const :override, T.nilable(T::Boolean)
  end

  class SSRHints < T::Struct
    const :highly_cacheable, T.nilable(T::Boolean)
    const :no_js_experience, T.nilable(T::Boolean)
  end

  class SelectiveSSR
    sig { returns(SSRMetadata) }
    attr_reader :metadata

    sig { returns(SSRHints) }
    attr_reader :hints

    sig { returns(Browser::Base) }
    attr_reader :browser

    sig { params(metadata: SSRMetadata, hints: SSRHints).void }
    def initialize(metadata:, hints:)
      @metadata = metadata
      @hints = hints
      @browser = Browser.new(metadata.user_agent)
    end

    sig { returns(Integer) }
    def tier
      return @tier if defined?(@tier)

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

    def tier0?
      metadata.override
    end

    def tier1?
      bot? || !metadata.logged_in || hints.highly_cacheable || hints.no_js_experience
    end

    def tier2?
      mobile? || !major_browser? || !major_os? || low_powered_device?
    end

    def tier4?
      # we don't want to match override `nil`
      metadata.override == false || metadata.spammy
    end

    def bot?
      metadata.robot || browser.bot?
    end

    def mobile?
      metadata.mobile || browser.device.mobile? || browser.device.tablet?
    end

    def major_browser?
      browser.chromium_based? || browser.safari? || browser.firefox?
    end

    def major_os?
      platform.windows? || platform.mac? || platform.linux?
    end

    def low_powered_device?
      metadata.cpu_bucket == "sm" || metadata.cpu_bucket == "md"
    end

    sig { returns(Browser::Platform) }
    def platform
      browser.platform
    end
  end
end
