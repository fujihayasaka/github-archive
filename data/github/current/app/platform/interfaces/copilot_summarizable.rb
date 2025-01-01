# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module CopilotSummarizable
      extend T::Helpers

      include GitHub::ResilienceMixin
      include Platform::Interfaces::Base

      requires_ancestor { GraphQL::Schema::Object }

      description "An object that supports content summarization by Copilot."

      visibility :under_development, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      field :can_be_summarized, Boolean,
        "Indicates whether this particular object can be summarized by Copilot for the current viewer.", null: false,
        visibility: { internal: { environments: [:enterprise] }, under_development: { environments: [:dotcom] } }

      def can_be_summarized
        db_error_fallback = -> do
          raise Platform::Errors::ServiceUnavailable, "Copilot summaries are currently unavailable."
        end

        case @object
        when ::Issue
          with_async_database_error_fallback(
            Issue::CopilotSummarizer.async_can_be_summarized?(viewer: @context[:viewer], issue: @object),
            fallback: db_error_fallback,
          )
        when ::Discussion
          with_async_database_error_fallback(
            Discussion::CopilotSummarizer.async_can_be_summarized?(viewer: @context[:viewer], discussion: @object),
            fallback: db_error_fallback,
          )
        else
          false
        end
      end
    end
  end
end
