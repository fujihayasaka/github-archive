# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DisableGists < Platform::Mutations::Base
      description "Disable gists. ex for TOS or DMCA violations"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :gist_ids, [ID], "The global relay ids of gists to disable.", required: true, loads: Objects::Gist, as: :gists
      argument :reason, String, "Reason for disabling the gists", required: true
      argument :disabling_detail, String, "Detailed reason tag for disabling the gists", required: false
      argument :instructions, String, "Message emailed to owner", required: false
      argument :async, Boolean, "Perform in a background job", required: false, default_value: false
      argument :staff_note, String, "Adds a staff note to the gist owner", required: false
      argument :dmca_takedown_url, String, "URL to the takedown notice", required: false
      argument :dsa, Inputs::DsaRepositoryModerationAction, "The DSA moderation fields.", required: false
      argument :dsa_required, Boolean, "False if the violation was deemed inauthentic and should not publish a ModerationAction event", required: false, default_value: true
      argument :email_template, String, "The email template sent to the gist owner (and fork owners if selected)", required: false

      field :successes, [Objects::Gist], "The gists that were successfully disabled.", null: true
      field :failures, [Objects::Gist], "The gists that failed to be disabled.", null: true
      field :errors, [String], "The errors that caused failures.", null: true

      def resolve(gists:, **inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to disable gists."
        end

        dmca_takedown_url = inputs[:dmca_takedown_url]
        reason = inputs[:reason]
        if reason == "dmca" && (dmca_takedown_url.blank? || dmca_takedown_url !~ GitRepositoryAccess::TAKEDOWN_URL_FORMAT)
          raise Errors::Validation.new "DMCA takedown requests requires a valid dmca_takedown_url"
        end

        staff_note = inputs[:staff_note]
        async = inputs[:async]
        results = []

        if gists.size > 20 && !async
          raise Errors::Validation.new "Cannot disable more than 20 gists at once due to synchronous processing overload. " \
                                       "Received #{gists.size} gists."
        end

        gists.each do |gist|
          gist_access = gist.access
          next if gist_access.disabled? && reason != "dmca"

          if staff_note.present? && !GitHub.enterprise?
            StaffNote.create(
              user: context[:viewer],
              notable: gist.owner,
              note: staff_note,
            )
          end

          if async
            gist.disable_access(
              reason,
              context[:viewer],
              instructions: inputs[:instructions],
              disabling_detail: inputs[:disabling_detail],
              dmca_takedown: dmca_takedown_url,
              email_template: inputs[:email_template],
              dsa_required: inputs[:dsa_required],
              content_formats: inputs[:dsa]&.content_formats,
              source: inputs[:dsa]&.dsa_source,
              tos_reason: inputs[:dsa]&.tos_reason,
            )
          else
            result = gist_access.disable(
              reason,
              context[:viewer],
              instructions: inputs[:instructions],
              disabling_detail: inputs[:disabling_detail],
              dmca_takedown: dmca_takedown_url,
              email_template: inputs[:email_template],
              dsa_required: inputs[:dsa_required],
              content_formats: inputs[:dsa]&.content_formats,
              source: inputs[:dsa]&.dsa_source,
              tos_reason: inputs[:dsa]&.tos_reason,
            )
            results << result
          end
        end

        # for async, we can't get results of the calls immediately, so just return the input gists
        if async
          return { successes: gists, failures: {}, errors: {} }
        end

        # Split results from the disable calls
        all_successes = results.flat_map { |result| result[:successes] }
        all_failures = results.flat_map { |result| result[:failures] }
        all_errors = results.flat_map { |result| result[:errors] }

        { successes: all_successes, failures: all_failures, errors: all_errors }
      end
    end
  end
end
