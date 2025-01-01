# typed: strict
# frozen_string_literal: true

module Growth
  class PricingSummaryComponent < ApplicationComponent
    sig { returns T::Hash[Symbol, T.untyped] }
    attr_reader :system_arguments

    sig { params(system_arguments: T.untyped).void }
    def initialize(**system_arguments)
      @system_arguments = T.let({
        display: :flex,
        direction: :column,
        mb: 3,
        border: :bottom,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
    end

    renders_one :title, lambda { |tag: :h3, **system_arguments|
      arguments = T.let({
        font_size: 4,
        font_weight: :bold,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Primer::Beta::Heading.new(
        **T.unsafe({ tag: tag, **arguments }),
      )
    }

    renders_one :subtitle, lambda { |tag: :span, **system_arguments|
      arguments = T.let({
        font_size: 5,
        color: :muted,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Primer::Beta::Text.new(
        **T.unsafe({ tag: tag, **arguments }),
      )
    }

    renders_many :line_items, lambda { |**system_arguments|
      arguments = T.let({
        mb: 3,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Growth::PricingLineItemComponent.new(
        **arguments,
      )
    }

    renders_one :sales_tax, lambda { |**system_arguments|
      arguments = T.let({
        mb: 3,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Growth::PricingLineItemComponent.new(
        **arguments,
      )
    }

    renders_many :totals, lambda { |**system_arguments|
      arguments = T.let({
        mb: 3,
        font_weight: :bold,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Growth::PricingLineItemComponent.new(
        **arguments,
      )
    }
  end
end
