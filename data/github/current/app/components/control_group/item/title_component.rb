# typed: strict
# frozen_string_literal: true

module ControlGroup
  module Item
    class TitleComponent < ApplicationComponent
      sig { params(tag: Symbol).void }
      def initialize(tag: :span)
        @tag = tag
      end

      sig { returns(String) }
      def call
        content_tag(@tag, content, class: "ControlGroup-item-title")
      end
    end
  end
end
