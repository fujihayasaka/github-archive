# typed: strict
# frozen_string_literal: true

module Growth
  class SeatsPricingCardComponent < ApplicationComponent
    sig { returns T::Hash[Symbol, T.untyped] }
    attr_reader :system_arguments

    sig { returns String }
    attr_reader :per, :seat_label

    sig { params(seat_price: Billing::Money, seat_label: String, per: String, variant: Symbol, system_arguments: Primer::SystemArgumentsValue).void }
    def initialize(seat_price:, seat_label: "seat", per: "year", variant: :default, **system_arguments)
      @seat_price = seat_price
      @seat_label = seat_label
      @per = per
      @system_arguments = T.let(
        {
          display: :flex,
          direction: :column,
          border: true,
          border_radius: 2,
          p: 3,
          style: "gap: 16px;"
        }.merge(system_arguments),
        T::Hash[Symbol, T.untyped]
      )
    end

    sig { returns(String) }
    memoize def seat_price_in_dollars
      @seat_price.format(no_cents_if_whole: true)
    end

    renders_one :title, lambda { |**system_arguments|
      arguments = T.let(
        {
          font_weight: :bold,
        }.merge(system_arguments),
        T::Hash[Symbol, T.untyped]
      )
      Primer::Box.new(
        **arguments,
      )
    }

    renders_one :toggle, lambda { |**system_arguments|
      arguments = system_arguments
      Primer::Alpha::SegmentedControl.new(
        **arguments,
      )
    }

    renders_one :notice, lambda { |**system_arguments|
      arguments = system_arguments
      arguments = T.let(
        {
          spacious: :false,
          font_size: 6,
          dismissible: false,
          icon: :info,
          scheme: :default,
          mb: 0,
          # 12px isn't a supported padding size in Primer, so we need to override it here.
          style: "padding: 12px; !important"
        }.merge(system_arguments),
        T::Hash[Symbol, T.untyped]
      )
      Primer::Beta::Flash.new(
        **arguments,
      )
    }

    renders_one :description, lambda { |**system_arguments|
      arguments = T.let(
        {
          font_size: 6,
          color: :muted,
          mb: 0,
        }.merge(system_arguments),
        T::Hash[Symbol, T.untyped]
      )
      Primer::Box.new(
        **arguments
      )
    }

    renders_one :stepper_component, lambda { |**system_arguments|
      arguments = system_arguments
      arguments[:type] = :plan_upgrade unless arguments.key?(:type)
      arguments[:my] = 0 unless arguments.key?(:my)
      arguments[:pt] = 2 unless arguments.key?(:pt)
      Billing::Settings::Upgrade::StepperComponent.new(**arguments)
    }
  end
end
