# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class TableHeaderLinkComponent < ApplicationComponent
    extend T::Sig

    sig do
      params(
        icon: Symbol,
        href: String,
        text: String,
        is_highlighted: T::Boolean,
        js_slot_class: String,
        test_selector: String,
      ).void
    end
    def initialize(
      icon:,
      href:,
      text:,
      is_highlighted:,
      js_slot_class:,
      test_selector:
    )
      @icon = T.let(icon, Symbol)
      @href = T.let(href, String)
      @text = T.let(text, String)
      @is_highlighted = T.let(is_highlighted, T::Boolean)
      @js_slot_class = T.let(js_slot_class, String)
      @test_selector = T.let(test_selector, String)
    end

    sig { returns(Symbol) }
    def text_color
      @is_highlighted ? :default : :muted
    end

    sig { returns(Symbol) }
    def text_weight
      @is_highlighted ? :bold : :normal
    end
  end
end
