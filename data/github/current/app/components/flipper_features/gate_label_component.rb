# typed: true
# frozen_string_literal: true

module FlipperFeatures
  class GateLabelComponent < ApplicationComponent
    include GitHub::Memoizer

    DOCS_URL = "https://thehub.github.com/engineering/products-and-services/dotcom/features/feature-flags/overview"

    # As a follow up, we will replace DOCS_URL with a link to filter by the gate
    STATE_MATRIX = {
      fully_enabled: {
        text: FlipperGate::STATE_MATRIX.fetch(:fully_enabled),
        scheme: :done,
        href: DOCS_URL,
      },
      staff_shipped: {
        text: FlipperGate::STATE_MATRIX.fetch(:staff_shipped),
        scheme: :default,
        href: DOCS_URL,
      },
      actor_or_percentage: {
        text: FlipperGate::STATE_MATRIX.fetch(:actor_or_percentage),
        scheme: :secondary,
        href: DOCS_URL,
      },
      fully_disabled: {
        text: FlipperGate::STATE_MATRIX.fetch(:fully_disabled),
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
      return :fully_disabled if fully_disabled?
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
