# typed: strict
# frozen_string_literal: true

module ContextRegion
  class CopilotCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Copilot"
    end

    sig { override.returns(Crumb) }
    def parent
      RootCrumb.new
    end
  end
end
