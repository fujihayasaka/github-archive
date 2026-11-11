# typed: strict
# frozen_string_literal: true

module ControlGroup
  class ItemComponent < ApplicationComponent
    renders_one :title, lambda { |tag: :span|
      ControlGroup::Item::TitleComponent.new(tag: tag)
    }
    renders_one :description
    renders_one :leading_icon, lambda { |icon:, size: :small|
      ControlGroup::Item::LeadingIconComponent.new(icon: icon, size: size)
    }
    renders_one :leading_visual
    renders_one :control
    renders_one :footer

    sig do
      params(
        href: T.nilable(String),
        nested_level: Integer,
        disabled: T::Boolean,
        test_selector: T.nilable(String),
      ).void
    end
    def initialize(href: nil, nested_level: 0, disabled: false, test_selector: nil)
      @href = href
      @nested_level = nested_level
      @disabled = disabled
      @test_selector = test_selector
    end

    private

    sig { returns(String) }
    def container_classes
      class_names(
        "ControlGroup-item",
        "ControlGroup-item--disabled": @disabled,
        "ControlGroup-item--link": @href && !@disabled,
      )
    end

    sig { returns(String) }
    def container_style
      "--nested-level: #{@nested_level};"
    end
  end
end
