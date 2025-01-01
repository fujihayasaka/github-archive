# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class StaffDeleteRepositories < Platform::Mutations::Base
      description "Delete multiple repositories."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :repository_ids, [ID], "The global relay ids of repositories to delete.", required: true, loads: Objects::Repository, as: :repositories
      argument :staff_note, String, "Adds a staff note to the repository owner", required: false
      argument :async, Boolean, "Whether to delete the repositories asynchronously.", required: false, default_value: true

      field :success, [Objects::Repository], "The deleted repositories.", null: true
      field :failure, [Objects::Repository], "The repositories that failed to delete", null: true

      def resolve(repositories:, **inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to delete repositories."
        end

        staff_note = inputs[:staff_note]

        success = []
        failure = []

        applied_users = Set.new

        repositories.each do |repository|
          begin
            if staff_note.present? && !GitHub.enterprise? && !applied_users.include?(repository.owner.id)
              StaffNote.create(
                user: context[:viewer],
                notable: repository.owner,
                note: staff_note,
              )
              applied_users.add(repository.owner.id)
            end
            repository.remove(context[:viewer], synchronous: !inputs[:async], staff: true)
            success << repository
          rescue => e # rubocop:todo Lint/GenericRescue
            failure << repository
            Failbot.report(e, repo_id: repository.id)
          end
        end

        { success: success, failure: failure }
      end
    end
  end
end
