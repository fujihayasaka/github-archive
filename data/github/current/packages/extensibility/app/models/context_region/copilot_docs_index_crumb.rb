# typed: strict
# frozen_string_literal: true

module ContextRegion
  class CopilotDocsIndexCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Docs"
    end

    sig { override.returns(Crumb) }
    def parent
      CopilotCrumb.new
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :copilot_for_docs_index_path
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      []
    end
  end
end
