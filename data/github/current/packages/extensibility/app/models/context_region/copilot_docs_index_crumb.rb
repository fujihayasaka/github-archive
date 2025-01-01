# typed: true
# frozen_string_literal: true

module ContextRegion
  class CopilotDocsIndexCrumb < Crumb
    def label
      "Docs"
    end

    def parent
      CopilotCrumb.new
    end

    def path_name
      :copilot_for_docs_index_path
    end

    def path_args

    end
  end
end
