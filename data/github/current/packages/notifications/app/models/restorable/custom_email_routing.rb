# typed: true
# frozen_string_literal: true

class Restorable
  class CustomEmailRouting < ApplicationRecord::Domain::Restorables
    # A set of common restorable type model helper methods.
    extend TypeHelpers

    belongs_to :restorable

    validates_presence_of :restorable_id, :organization_id, :email
    validates_uniqueness_of :restorable_id, scope: [:restorable_id, :organization_id]

    # Internal: Create a set of custom_email_routing records.
    #
    # restorable - Restorable parent instance.
    # org_id_and_email_hash - A hash of org ids to email strings
    def self.backup(restorable:, org_id_and_email_hash:)
      save_models(restorable, org_id_and_email_hash)
    end

    # Internal: Restore custom email routings for this user.
    #
    # restorable - Restorable parent instance.
    # user - User instance.
    def self.restore(restorable:, user:)
      restorable.restoring(:restorable_custom_email_routings)
      notifiable_emails = user.notifiable_emails

      measure_restore_time do
        user_notification_settings(user) do |settings|
          restorable.custom_email_routings.each do |email_routing|
            email_key = "org-#{email_routing.organization_id}"
            email = email_routing.email

            if settings.default_email_address != email
              settings.set_notification_email(email_key, email_routing.email)
            end
          end

          settings.clear_unverified_emails(notifiable_emails)
        end
      end

      restorable.restored(:restorable_custom_email_routings)
    end

    # Internal: Bulk insert sql.
    #
    # Returns a String.
    def self.insert_ignore_sql
      <<-SQL
        INSERT IGNORE INTO
          restorable_custom_email_routings
          (restorable_id,organization_id,email)
        :values
      SQL
    end

    # Internal: Create an array with needed values from models.
    #
    # restorable_id - Integer id of Restorable.
    # org_id_and_email_hash - A hash of org ids to email strings
    #
    # Returns an Array of arrays.
    def self.values(restorable_id, org_id_and_email_hash)
      org_id_and_email_hash.map do |org_id, email|
        [
          restorable_id,
          org_id,
          email,
        ]
      end
    end

    # Internal: The metric name for statsd.
    #
    # Returns a Symbol.
    def self.metric_name
      :custom_email_routing
    end

    def self.user_notification_settings(user)
      GitHub.newsies.get_and_update_settings(user) do |settings|
        yield(build_user_notification_settings(settings))
      end
    end

    def self.build_user_notification_settings(settings)
      UserNotificationSettings.new(settings)
    end

    class UserNotificationSettings
      def initialize(settings)
        @settings = settings
      end

      def default_email_address
        @settings.default_email.address
      end

      def set_notification_email(subject_key, email_address)
        @settings.email(subject_key, email_address)
      end

      def clear_unverified_emails(notifiable_emails)
        @settings.clear_unverified_emails(notifiable_emails)
      end
    end
  end
end
