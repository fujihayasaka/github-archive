# typed: true
# frozen_string_literal: true

module Site
  module Header
    module ContextRegion
      class CompactCrumbComponent < ApplicationComponent
        attr_reader :crumb

        def initialize(crumb)
          @crumb = crumb
        end
      end
    end
  end
end
