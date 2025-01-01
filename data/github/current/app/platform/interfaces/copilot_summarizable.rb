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
        false
      end
    end
  end
end
