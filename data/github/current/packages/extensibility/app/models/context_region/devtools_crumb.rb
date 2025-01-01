# typed: true
# frozen_string_literal: true

module ContextRegion
  class DevtoolsCrumb < Crumb
    def label
      "Developer tools"
    end

    def path_name
      :devtools_path
    end
  end
end
