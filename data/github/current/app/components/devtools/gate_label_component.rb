# typed: true
# frozen_string_literal: true

module Devtools
  class GateLabelComponent < ApplicationComponent
    include GitHub::Memoizer

    DOCS_URL = "https://thehub.github.com/engineering/products-and-services/dotcom/features/feature-flags/overview"

    STATE_MATRIX = {
      fully_enabled: {
        text: "shipped",
        scheme: :done,
        href: DOCS_URL,
      },
      staff_shipped: {
        text: "staff-shipped",
        scheme: :default,
        href: DOCS_URL,
      },
      actor_or_percentage: {
        text: "testing",
        scheme: :secondary,
        href: DOCS_URL,
      },
      fully_disabled: {
        text: "disabled",
        scheme: :warning,
        href: DOCS_URL,
      },
    }.freeze

    def initialize(**kwargs)
      @feature = kwargs.fetch(:feature)
    end

    def label_text
      state_value(:text)
    end

    def scheme
      state_value(:scheme)
    end

    def href
      state_value(:href)
    end

    private

    memoize def state
      return :fully_enabled if @feature.prelude_fully_enabled?
      return :staff_shipped if staff_shipped?
      return :actor_or_percentage if actor_or_percentage?
      :fully_disabled if fully_disabled?
    end

    def staff_shipped?
      @feature.prelude_staff_shipped? && !@feature.prelude_fully_enabled?
    end

    def actor_or_percentage?
      @feature.prelude_actor_or_percentage? && !staff_shipped?
    end

    def fully_disabled?
      !actor_or_percentage?
    end

    def state_value(key)
      raise ArgumentError, "key must be one of #{STATE_MATRIX.keys}" unless key
      STATE_MATRIX.fetch(state)[key]
    end

    def render?
      state
    end
  end
end
