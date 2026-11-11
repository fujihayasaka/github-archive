# typed: strict
# frozen_string_literal: true

module ContextRegion
  class DevtoolsCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Developer tools"
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :devtools_path
    end
  end
end
