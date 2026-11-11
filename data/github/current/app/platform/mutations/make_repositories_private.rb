# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MakeRepositoriesPrivate < Platform::Mutations::Base
      docs_category :repos
      description "Change repository visibility to private. For staff use during security incidents."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      read_arguments_from_replicas!

      argument :repository_ids, [ID], "The global relay ids of repositories to make private.",
               required: true, loads: Objects::Repository, as: :repositories
      argument :staff_note, String, "Adds a staff note to the repository owner", required: false
      argument :async, Boolean, "Perform in a background job. Automatically enabled for more than 20 repositories.", required: false, default_value: true

      field :repositories, Connections.define(Objects::Repository), "The repositories being made private.", null: true do
        argument :order_by, Inputs::RepositoryOrder, "Ordering options for repositories returned from the connection",
                 required: false, default_value: { field: "name", direction: "ASC" }
      end

      def resolve(repositories:, staff_note: nil, async: true)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to change repository visibility."
        end

        # Force async for large batches to avoid timeout issues
        async = true if repositories.size > 20

        results = []
        repositories.each do |repository|
          if staff_note.present? && !GitHub.enterprise?
            StaffNote.create(
              user: context[:viewer],
              notable: repository.owner,
              note: staff_note,
            )
          end

          orchestration = RepositoryOrchestration.set_visibility(
            repository,
            actor: context[:viewer],
            visibility: "private"
          )

          orchestration.execute(synchronous: !async)
          results << repository
        end

        { repositories: results }
      end
    end
  end
end
