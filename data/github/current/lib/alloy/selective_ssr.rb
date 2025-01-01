# typed: true
# frozen_string_literal: true

module Alloy
  class SelectiveSSR
    extend T::Sig

    sig { params(metadata: SSRMetadata, hints: T.nilable(SSRHints)).returns(T::Boolean) }
    def self.should_enable_ssr(metadata, hints = nil)
      tier = self.select_tier(metadata, hints)

      if tier == Tier::TIER_1
        true
      elsif tier == Tier::TIER_2
        !!metadata.is_mobile
      else
        false
      end
    end

    sig { params(metadata: SSRMetadata, hints: T.nilable(SSRHints)).returns(Integer) }
    def self.select_tier(metadata, hints = nil)
      is_robot = metadata.is_robot
      is_logged_in = metadata.is_logged_in
      is_mobile = metadata.is_mobile
      highly_cacheable = hints&.highly_cacheable
      no_js_experience = hints&.no_js_experience

      if is_robot || !is_logged_in || highly_cacheable || no_js_experience
        Tier::TIER_1
      elsif is_mobile
        Tier::TIER_2
      else
        Tier::TIER_3
      end
    end
  end

  class SSRMetadata
    attr_accessor :is_logged_in, :is_robot, :is_mobile, :is_spammy

    def initialize(is_logged_in: false, is_robot: false, is_mobile: false, is_spammy: false)
      @is_logged_in = is_logged_in
      @is_robot = is_robot
      @is_mobile = is_mobile
      @is_spammy = is_spammy
    end
  end

  class SSRHints
    attr_accessor :highly_cacheable, :no_js_experience, :highly_dynamic_content

    def initialize(highly_cacheable: false, no_js_experience: false, highly_dynamic_content: false)
      @highly_cacheable = highly_cacheable
      @no_js_experience = no_js_experience
      @highly_dynamic_content = highly_dynamic_content
    end
  end

  module Tier
    TIER_1 = 1
    TIER_2 = 2
    TIER_3 = 3
  end
end
