# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      class TierLabelComponent < ApplicationComponent
        # achievable - Instance of an Achievable subclass.
        # tier - Integer indicating the highest unlocked tier of this Achievable.
        # kwargs - Additional keyword arguments passed to the label.
        def initialize(achievable:, tier:, **kwargs)
          @achievable = achievable
          @tier = tier
          @kwargs = kwargs
        end

        def call
          render(Primer::Beta::Label.new(
            font_size: :small,
            font_weight: :bold,
            box_shadow: :medium,
            classes: "achievement-tier-label achievement-tier-label--#{tier.name}",
            **@kwargs,
          ).with_content("x#{tier.index + 1}"))
        end

        private

        def render?
          tier.valid? && tier.index > 0
        end

        def tier
          @achievable.tier(@tier)
        end
      end
    end
  end
end
