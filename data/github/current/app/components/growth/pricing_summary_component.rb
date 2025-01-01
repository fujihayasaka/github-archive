# typed: strict
# frozen_string_literal: true

module Growth
  class PricingSummaryComponent < ApplicationComponent
    extend T::Sig

    sig { returns T::Hash[Symbol, T.untyped] }
    attr_reader :system_arguments

    sig { params(system_arguments: T.untyped).void }
    def initialize(**system_arguments)
      @system_arguments = T.let({
        display: :flex,
        direction: :column,
        border: true,
        border_radius: 2,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
    end

    renders_one :title, lambda { |tag: :h3, **system_arguments|
      arguments = T.let({
        font_size: 4,
        font_weight: :bold,
        p: 3,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Primer::Beta::Heading.new(
        **T.unsafe({ tag: tag, **arguments }),
      )
    }

    renders_many :line_items, lambda { |**system_arguments|
      arguments = T.let({
        px: 3,
        pb: 3,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Growth::PricingLineItemComponent.new(
        **arguments,
      )
    }

    renders_one :total, lambda { |**system_arguments|
      arguments = T.let({
        border: :top,
        p: 3,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Growth::PricingLineItemComponent.new(
        **arguments,
      )
    }

    renders_one :sales_tax, lambda { |**system_arguments|
      arguments = T.let({
        px: 3,
        pb: 3,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Growth::PricingLineItemComponent.new(
        **arguments,
      )
    }
  end
end
