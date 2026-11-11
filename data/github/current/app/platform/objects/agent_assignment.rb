# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AgentAssignment < Platform::Objects::Base
      description "Represents an agent assignment to an issue."

      visibility :internal

      def self.async_api_can_access?(permission, object)
        object.async_source_repository.then do |source_repository|
          permission.typed_can_see?("Repository", source_repository)
        end
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_source_repository.then do |source_repository|
          permission.typed_can_see?("Repository", source_repository)
        end
      end

      scopeless_tokens_as_minimum

      field :assignee,
        Objects::Bot,
        "The agent that was assigned.",
        null: true

      def assignee
        @object.async_assignee
      end

      field :assigner,
        Interfaces::Actor,
        "The actor who assigned the agent.",
        null: true

      def assigner
        @object.async_assigner
      end
    end
  end
end
