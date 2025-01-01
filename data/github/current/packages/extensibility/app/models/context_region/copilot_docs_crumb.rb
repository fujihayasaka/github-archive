# typed: true
# frozen_string_literal: true

module ContextRegion
  class CopilotDocsCrumb < Crumb
    def label
      object[:name]
    end

    def parent
      CopilotDocsIndexCrumb.new
    end

    def path_name
      :copilot_for_docs_docset_path
    end

    def path_args
      [object[:name]]
    end
  end
end
