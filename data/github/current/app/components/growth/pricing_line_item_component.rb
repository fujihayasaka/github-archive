# typed: strict
# frozen_string_literal: true

module Growth
  class PricingLineItemComponent < ApplicationComponent
    sig { returns T::Hash[Symbol, T.untyped] }
    attr_reader :system_arguments

    sig { params(system_arguments: Primer::SystemArgumentsValue).void }
    def initialize(**system_arguments)
      @system_arguments = T.let({
        display: :flex,
        direction: :row,
        justify_content: :space_between,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
    end

    renders_one :title, lambda { |tag: :h4, **system_arguments|
      arguments = T.let({
        font_size: 5,
        font_weight: :bold,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Primer::Beta::Heading.new(
        **T.unsafe({ tag: tag, **arguments }),
      )
    }

    renders_one :description, lambda { |**system_arguments|
      arguments = T.let({
        color: :muted,
        font_size: 6,
      }.merge(system_arguments), T::Hash[Symbol, T.untyped])
      Primer::Box.new(
        **arguments,
      )
    }

    renders_one :cost, lambda { |**system_arguments|
      arguments = system_arguments
      Primer::Box.new(
        **arguments,
      )
    }
  end
end
