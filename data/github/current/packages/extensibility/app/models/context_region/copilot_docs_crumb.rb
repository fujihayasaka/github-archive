# typed: strict
# frozen_string_literal: true

module ContextRegion
  class CopilotDocsCrumb < Crumb
    sig { override.returns(String) }
    def label
      object&.[](:name) || ""
    end

    sig { override.returns(Crumb) }
    def parent
      CopilotDocsIndexCrumb.new
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :copilot_for_docs_docset_path
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      [object&.[](:name)].compact
    end
  end
end
