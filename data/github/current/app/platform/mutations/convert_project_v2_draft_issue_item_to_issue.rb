# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ConvertProjectV2DraftIssueItemToIssue < Platform::Mutations::Base
      description "Converts a projectV2 draft issue item to an issue."

      minimum_accepted_scopes %w[public_repo project]

      argument :item_id, ID, "The ID of the draft issue ProjectV2Item to convert.", required: true, loads: Objects::ProjectV2Item
      argument :repository_id, ID, "The ID of the repository to create the issue in.", required: true, loads: Objects::Repository

      field :item, Objects::ProjectV2Item, "The updated project item.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, item:, repository:, **inputs)
        project_permission = item.async_memex_project.then do |project|
          project.async_owner.then do |owner|
            current_org = owner if owner.organization?
            permission.access_allowed?(
              :project_v2_write,
              current_org: current_org,
              resource: project,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end

        repo_permission = permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed? :open_issue, resource: repository, repo: repository, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true
        end

        Promise.all([project_permission, repo_permission]).then do |project, repository|
          project && repository
        end
      end

      def resolve(item:, repository:, **inputs)
        context[:permission].authorize_content(:issue, :create, repo: repository)

        begin
          MemexProjectItem::ConvertToIssue.call(
            memex_project_item: item,
            actor: context[:viewer],
            repository: repository,
          )

          { item: item }
        rescue MemexProjectItem::ConvertToIssue::Error => e
          raise Errors::Unprocessable.new(e.message)
        rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotDestroyed
          Storage::UserAssetTransfer::DraftToRepositoryTransferRollback.rollback_to(item.memex_project, context[:viewer], item.content.body)
          raise Errors::Unprocessable.new("Unable to create new issue from draft issue")
        rescue Storage::UserAssetTransfer::Transfer::TransferError => e
          raise Errors::Unprocessable.new("Unable to transfer assets to new issue. Please try again.")
        rescue ActiveRecord::RecordInvalid => invalid
          raise Errors::Unprocessable.new(invalid.record.errors.full_messages.join(", "))
        end
      end
    end
  end
end
