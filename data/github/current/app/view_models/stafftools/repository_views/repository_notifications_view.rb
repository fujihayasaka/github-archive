# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class RepositoryNotificationsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :current_repository, :audit_log_data

      # Only refs for branches/tags will create notifications
      VALID_REF_REGEX = %r{\Arefs/(heads|tags)/}

      # Public: is there a configured email hook for this repository
      #
      # Returns Boolean
      def notifications_configured?
        hook.present?
      end

      # Public: return the configured email hook for this repository
      #
      # Returns Hook
      def hook
        @hook ||= Hook.email_hooks_for_target(current_repository).first
      end

      def show_splunk_links?
        !GitHub.enterprise?
      end

      # Public: build a link to search splunk for a specific email address
      def splunk_email_query(email)
        "index=prod-email #{email}"
      end

      # Public: build a link to search splunk for a specific email based on a push
      #
      # The `message_id` format here matches the one generated in
      # RepositoryPushNotificationMailer#message_id
      #   (https://github.com/github/github/blob/4f41564ab1b20a8666483e87c8faee93643896e7/app/mailers/repository_push_notification_mailer.rb#L102-L113)
      #
      # Returns a link
      def splunk_message_id_query(ref:, before:, after:)
        before_short = before.slice(0, 6)
        after_short = after.slice(0, 6)
        message_id = "#{current_repository.name_with_owner}/push/#{ref}/#{before_short}-#{after_short}"

        "index=prod-email #{message_id}"
      end

      # Public: return list of actual recipients
      #
      # Due to legacy data issues, we don't necessarily email everyone listed.
      # This method returns which emails we _actually_ expect to email
      #
      # Returns Array of Strings
      def recipient_emails
        raw_address = hook&.config["address"]
        return [] unless raw_address

        RepositoryPushNotificationMailer.recipients_from_config(raw_address)
      end

      # Public: gets the recent reflog entries for the repo if available
      #         filters out internal refs that are not relevant to "pushes"
      #
      # Returns Array of LoggedPush objects
      def reflog_entries
        return @reflog_entries if defined?(@reflog_entries)
        return nil unless current_repository.online?

        @reflog_entries ||= current_repository.reflog(@ref, { squash: true, page: 1 })
                                              .reject { |push| valid_push_targets(push.targets).empty? }
      end

      # Public: Filters a list of LoggedPushTarget objects to only return
      #         refs that are relevant to "pushes"
      def valid_push_targets(targets)
        targets.select { |target| VALID_REF_REGEX.match(target.ref) }
      end
    end
  end
end
