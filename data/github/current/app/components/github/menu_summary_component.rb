# typed: true
# frozen_string_literal: true

module GitHub
  class MenuSummaryComponent < ApplicationComponent
    renders_one :body

    def initialize(text: nil, menu: nil, replaceable: false, default_selection_text: nil, classes: nil)
      @text = text
      @replaceable = menu ? menu.replaceable? : replaceable
      @default_selection_text = menu ? menu.default_selection_text : default_selection_text
      @classes = classes
    end
  end
end
