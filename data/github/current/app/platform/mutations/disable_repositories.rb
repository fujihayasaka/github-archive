# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DisableRepositories < Platform::Mutations::Base
      description "Disable repositories. ex for TOS violations"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :repository_ids, [ID], "The global relay ids of repositories to disable.", required: true, loads: Objects::Repository, as: :repositories
      argument :reason, String, "Reason for disabling the repositories", required: true
      argument :disabling_detail, String, "Detailed reason tag for disabling the repositories", required: false
      argument :instructions, String, "Message emailed to owner", required: false
      argument :async, Boolean, "Perform in a background job", required: false, default_value: false
      argument :staff_note, String, "Adds a staff note to the repository owner", required: false
      argument :dmca_takedown_url, String, "URL to the takedown notice", required: false

      field :repositories, [Objects::Repository], "The disabled repositories.", null: true

      def resolve(repositories:, **inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to disable repositories."
        end

        dmca_takedown_url = inputs[:dmca_takedown_url]
        reason = inputs[:reason]
        if reason == "dmca" && (dmca_takedown_url.blank? || dmca_takedown_url !~ GitRepositoryAccess::TAKEDOWN_URL_FORMAT)
          raise Errors::Validation.new "DMCA takedown requests requires a valid dmca_takedown_url"
        end

        staff_note = inputs[:staff_note]
        repositories.each do |repository|
          repository_access = repository.access
          next if repository_access.disabled? && reason != "dmca"

          if staff_note.present? && !GitHub.enterprise?
            StaffNote.create(
              user: context[:viewer],
              notable: repository.owner,
              note: staff_note,
            )
          end

          if inputs[:async]
            repository.disable_access(
              reason,
              context[:viewer],
              instructions: inputs[:instructions],
              disabling_detail: inputs[:disabling_detail],
              dmca_takedown: dmca_takedown_url,
            )
          else
            repository_access.disable(
              reason,
              context[:viewer],
              instructions: inputs[:instructions],
              disabling_detail: inputs[:disabling_detail],
              dmca_takedown: dmca_takedown_url,
            )
          end
        end

        { repositories: repositories }
      end
    end
  end
end
