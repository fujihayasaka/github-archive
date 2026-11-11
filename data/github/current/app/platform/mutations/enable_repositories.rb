# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class EnableRepositories < Platform::Mutations::Base
      description "Enable repositories that were previously disabled"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      read_arguments_from_replicas!

      argument :repository_ids, [ID], "The global relay ids of repositories to enable.", required: true, loads: Objects::Repository, as: :repositories
      argument :async, Boolean, "Perform in a background job", required: false, default_value: false
      argument :staff_note, String, "Adds a staff note to the repository owner", required: false

      field :repositories, [Objects::Repository], "The enabled repositories.", null: true

      def resolve(repositories:, **inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to enable repositories."
        end

        unless repositories.any?
          raise Errors::Validation.new "No repositories provided"
        end

        if repositories.count > 50 && !inputs[:async]
          raise Errors::Validation.new "Enabling more than 50 repositories requires async to be set to true"
        end

        staff_note = inputs[:staff_note]
        repositories.each do |repository|
          repository_access = repository.access
          next if repository_access.enabled?

          if staff_note.present? && !GitHub.enterprise?
            StaffNote.create(
              user: context[:viewer],
              notable: repository.owner,
              note: staff_note,
            )
          end

          if inputs[:async]
            repository.enable_access(context[:viewer])
          else
            repository_access.enable(context[:viewer])
          end
        end

        { repositories: repositories }
      end
    end
  end
end
