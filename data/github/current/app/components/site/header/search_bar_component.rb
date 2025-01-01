# typed: strict
# frozen_string_literal: true

module Site
  module Header
    class SearchBarComponent < ApplicationComponent
      include CommandPaletteHelper

      renders_one :control
      renders_one :placeholder
      renders_one :narrow_control
    end
  end
end
