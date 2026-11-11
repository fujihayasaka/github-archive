# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Pinnable
      include Platform::Interfaces::Base
      docs_category :users
      include GitHub::ResilienceMixin

      description "Entities that can be pinned."

      field :viewer_can_pin, Boolean, description: "Check if the current viewer can pin this entity.", null: false

      def viewer_can_pin
        @object.async_repository.then do |repo|
          Issue::PermissionsDependency.async_can_manage_pinned_comment?(@context[:viewer], repo)
        end
      end

      field :viewer_can_unpin, Boolean, description: "Check if the current viewer can unpin this entity.", null: false

      def viewer_can_unpin
        @object.async_repository.then do |repo|
          Issue::PermissionsDependency.async_can_manage_pinned_comment?(@context[:viewer], repo)
        end
      end

      field :pinned_by, Platform::Objects::User, description: "The user who pinned this entity.", null: true, extras: [:execution_errors]

      def pinned_by(execution_errors:)
        with_async_database_error_fallback(
          @object.async_pinned_issue_comment.then do |pinned_issue_comment|
            next unless pinned_issue_comment

            Platform::Loaders::ActiveRecordAssociation.load(pinned_issue_comment, :pinned_by).then do |_user|
              pinned_issue_comment.safe_pinned_by
            end
          end,
          fallback: -> {
            execution_errors.add("Pinned by information is temporarily unavailable")
            nil
          }
        )
      end

      field :is_pinned, Boolean, description: "Indicates whether or not this entity is currently pinned.", null: true, extras: [:execution_errors]

      def is_pinned(execution_errors:)
        with_async_database_error_fallback(
          @object.async_pinned_issue_comment.then do |pinned_issue_comment|
            pinned_issue_comment.present?
          end,
          fallback: -> {
            execution_errors.add("Pinned status is temporarily unavailable")
            nil
          }
        )
      end

      field :pinned_at, Scalars::DateTime, description: "Identifies the date and time when this entity was pinned.", null: true, extras: [:execution_errors]

      def pinned_at(execution_errors:)
        with_async_database_error_fallback(
          @object.async_pinned_issue_comment.then do |pinned_issue_comment|
            pinned_issue_comment&.created_at
          end,
          fallback: -> {
            execution_errors.add("Pinned at information is temporarily unavailable")
            nil
          }
        )
      end
    end
  end
end
