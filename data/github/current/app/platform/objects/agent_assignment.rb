# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AgentAssignment < Platform::Objects::Base
      docs_category :users
      description "Represents an agent assignment to an issue."

      visibility :internal

      def self.async_api_can_access?(permission, object)
        object.async_subject_repository.then do |subject_repository|
          permission.typed_can_see?("Repository", subject_repository)
        end
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_subject_repository.then do |subject_repository|
          permission.typed_can_see?("Repository", subject_repository)
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
        @object.async_assigner.then do |assigner_user|
          next assigner_user unless assigner_user.is_a?(::ProgrammaticAccessBot)

          # Resolve ProgrammaticAccessBot to the underlying user so the Actor
          # interface can resolve the type. This handles legacy records created
          # before the model-level before_validation fix was added.
          Platform::Loaders::ActiveRecordAssociation.load(assigner_user, :user_programmatic_access).then do |upa|
            if upa
              Platform::Loaders::ActiveRecordAssociation.load(upa, :owner).then do |owner|
                owner || assigner_user
              end
            else
              assigner_user
            end
          end
        end
      end
    end
  end
end
