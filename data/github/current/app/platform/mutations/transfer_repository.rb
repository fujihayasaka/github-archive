# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class TransferRepository < Platform::Mutations::Base
      description "Transfer repository ownership"
      visibility :internal

      minimum_accepted_scopes ["repo"]

      argument :repository_id, ID, "The ID of the repository to transfer", required: true, loads: Objects::Repository
      argument :new_owner_id, ID, "The ID of the new owner for the repository", required: true, loads: Interfaces::RepositoryOwner
      argument :team_ids, [ID], "The IDs of the teams for the repository", required: false, loads: Objects::Team
      argument :new_name, String, "The new name of the repository", required: false

      field :repository, Objects::Repository, "The repository that was transferred", null: true

      def resolve(repository:, new_owner:, **inputs)
        viewer = context[:viewer]

        target_teams = inputs[:teams] || []
        new_name = inputs[:new_name]

        transfer_request = RepositoryTransfer.new(
          repository: repository,
          requester: viewer,
          target: new_owner,
          new_name: new_name,
        )

        if transfer_request.invalid?
          raise Errors::Unprocessable.new(transfer_request.errors.full_messages.to_sentence)
        end

        if RepositoryTransfer.requires_transfer_request?(target: new_owner, requester: viewer, repository_visibility: repository.visibility)
          RepositoryTransfer.start(repository, new_owner, viewer)
        else
          # For now, only the transfer_immediately case accepts new_name
          RepositoryTransfer.transfer_immediately(repository, new_owner, viewer, target_teams, transfer_request.new_name)
        end

        { repository: repository }
      end
    end
  end
end
