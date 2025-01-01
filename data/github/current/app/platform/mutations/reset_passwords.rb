# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ResetPasswords < Platform::Mutations::Base
      SIZE_LIMIT = 100

      description "Resets passwords and optionally sends security notification email"
      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :users, [Inputs::SecurityIncidentUser], "The user ids and optional notification data.", required: true
      argument :send_notification, Boolean, "Should a notification be sent for each password reset.", required: true
      argument :from, String, "Notification email reply to address.", required: true
      argument :subject, String, "Notification email subject.", required: true
      argument :template, String, "Mustache template for notification", required: true
      argument :staffnote, String, "Optional staffnote text", required: false

      field :users, [Objects::User], "The users that had their password reset.", null: true

      def resolve(**inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to reset passwords and send notifications."
        end

        if inputs[:users].size > SIZE_LIMIT
          raise Errors::Unprocessable.new("Request exceeded limit of #{SIZE_LIMIT} users.")
        end

        send_default_password_changed_notification = !inputs[:send_notification]

        data_by_user_id = {}
        inputs[:users].each do |security_incident_user|
          data_by_user_id[security_incident_user[:id]] = {}
          if extra_data = security_incident_user[:data]
            extra_data.each do |data|
              data_by_user_id[security_incident_user[:id]][data[:key].to_sym] = data[:value]
            end
          end
        end

        user_promises = inputs[:users].map do |security_incident_user|
          id = security_incident_user[:id]
          Platform::Helpers::NodeIdentification.async_typed_object_from_id(Objects::User, id, context)
        end

        notifier = GitHub::SendSecurityIncidentNotification.new(
          from: inputs[:from],
          subject: inputs[:subject],
          template: inputs[:template],
        )

        Promise.all(user_promises).then do |users|
          successfully_reset_users = []

          users.each do |user|
            next if user.employee?

            user.set_random_password(
              actor: context[:viewer],
              send_notification: send_default_password_changed_notification,
            )

            if inputs[:staffnote].present?
              StaffNote.create(user: context[:viewer], notable: user, note: inputs[:staffnote])
            end

            if inputs[:send_notification]
              data_by_user_id[user.global_relay_id][:login] = user.display_login
              notifier.perform_for_user(user, data_by_user_id[user.global_relay_id])
            end

            successfully_reset_users << user
          end

          { users: successfully_reset_users }
        end.sync
      end
    end
  end
end
