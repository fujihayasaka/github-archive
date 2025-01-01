# typed: true
# frozen_string_literal: true

module ContextRegion
  class CopilotCrumb < Crumb
    def label
      "Copilot"
    end

    def parent
      RootCrumb.new
    end
  end
end
