# typed: true
# frozen_string_literal: true

module Newsies

  # The Horcrux serializer.  The serializer transorms a
  # Newsies::Settings to an ActiveRecord attributes Hash, and
  # vice versa.  Used in Newsies::SettingsStore.
  module SettingsSerializer

    # Public: Transforms a settings Hash to an ActiveRecord attributes Hash.
    #
    # value - a Newsies::Settings
    #
    # Returns an attributes Hash for Settings::Model.
    def self.dump(value)
      if !value.is_a?(Settings)
        raise ArgumentError, "Requires a Setting but received a #{value.class}"
      end

      emails = value.emails.inject({}) do |memo, (key, email)|
        memo.update key => { email: email.address }
      end
      {
        emails: emails,
        auto_subscribe_repositories: value.auto_subscribe_repositories?,
        auto_subscribe_teams: value.auto_subscribe_teams?,
        notify_own_via_email: value.notify_own_via_email?,
        participating_web: value.participating_web?,
        participating_email: value.participating_email?,
        subscribed_web: value.subscribed_web?,
        subscribed_email: value.subscribed_email?,
        notify_comment_email: value.notify_comment_email?,
        notify_pull_request_review_email: value.notify_pull_request_review_email?,
        notify_pull_request_push_email: value.notify_pull_request_push_email?,
        vulnerability_cli: value.vulnerability_cli?,
        vulnerability_web: value.vulnerability_web?,
        vulnerability_email: value.vulnerability_email?,
        continuous_integration_web: value.continuous_integration_web?,
        continuous_integration_email: value.continuous_integration_email?,
        continuous_integration_failures_only: value.continuous_integration_failures_only?,
        org_deploy_key_email: value.org_deploy_key_email?,
      }
    end

    # Public: Transforms an attributes Hash to a settings Hash.
    #
    # record - An ActiveRecord class with a #data SerializedAttributes value,
    #          or the data Hash itself.
    #
    # Returns a Newsies::Settings.
    def self.load(record)
      if record.respond_to?(:raw_data)
        load_from_record(record)
      elsif record.respond_to?(:stringify_keys)
        load_from_hash(record)
      else
        raise ArgumentError, "Requires a Record or an Attributes hash: #{record.class}"
      end
    end

    # API-Private: extracted from SettingsSerializer.load
    #
    # Loads the settings from a record
    #
    def self.load_from_record(record)
      serialized_settings = record.raw_data.to_h.stringify_keys

      subscribed_and_participating_attrs = serialized_settings.slice("subscribed_settings", "participating_settings")
      subscribed_and_participating_attrs.merge! record.attributes.slice("participating_web", "participating_email", "subscribed_web", "subscribed_email")

      ::Newsies::Settings.new.tap do |settings|
        settings.auto_subscribe_repositories = record.auto_subscribe_repositories
        settings.auto_subscribe_teams = record.auto_subscribe_teams
        settings.notify_own_via_email = record.notify_own_via_email
        settings.notify_comment_email = record.notify_comment_email
        settings.notify_pull_request_review_email = record.notify_pull_request_review_email
        settings.notify_pull_request_push_email = record.notify_pull_request_push_email
        settings.vulnerability_web = record.vulnerability_web
        settings.vulnerability_cli = record.vulnerability_cli
        settings.vulnerability_email = record.vulnerability_email
        settings.continuous_integration_web = record.continuous_integration_web
        settings.continuous_integration_email = record.continuous_integration_email
        settings.continuous_integration_failures_only = record.continuous_integration_failures_only
        settings.org_deploy_key_email = record.org_deploy_key_email
        load_subscribed_and_participating_settings(settings, subscribed_and_participating_attrs)
        load_emails(settings, serialized_settings[Newsies::SETTINGS_EMAILS] || {})
      end
    end

    # DEPRECATED
    #
    # API-Private: extracted from SettingsSerializer.load
    #
    # Loads the settings from a hash
    #
    def self.load_from_hash(hash)
      serialized_settings = hash.stringify_keys

      ::Newsies::Settings.new.tap do |settings|
        settings.auto_subscribe = serialized_settings[Newsies::SETTINGS_AUTO_SUBSCRIBE]
        settings.notify_own_via_email = serialized_settings[Newsies::SETTINGS_NOTIFY_OWN_VIA_EMAIL]
        settings.notify_comment_email = serialized_settings[Newsies::SETTINGS_NOTIFY_COMMENT_EMAIL]
        settings.notify_pull_request_review_email = serialized_settings[Newsies::SETTINGS_NOTIFY_PULL_REQUEST_REVIEW_EMAIL]
        settings.notify_pull_request_push_email = serialized_settings[Newsies::SETTINGS_NOTIFY_PULL_REQUEST_PUSH_EMAIL]
        settings.vulnerability_web = serialized_settings[Newsies::SETTINGS_VULNERABILITY_WEB]
        settings.vulnerability_cli = serialized_settings[Newsies::SETTINGS_VULNERABILITY_CLI]
        settings.vulnerability_email = serialized_settings[Newsies::SETTINGS_VULNERABILITY_EMAIL]
        settings.continuous_integration_web = serialized_settings[Newsies::SETTINGS_CONTINUOUS_INTEGRATION_WEB]
        settings.continuous_integration_email = serialized_settings[Newsies::SETTINGS_CONTINUOUS_INTEGRATION_EMAIL]
        settings.continuous_integration_failures_only = serialized_settings[Newsies::SETTINGS_CONTINUOUS_INTEGRATION_FAILURES_ONLY]
        settings.org_deploy_key_email = serialized_settings[Newsies::SETTINGS_ORG_DEPLOY_KEY_EMAIL]
        load_subscribed_and_participating_settings(settings, serialized_settings)
        load_emails(settings, serialized_settings[Newsies::SETTINGS_EMAILS] || {})
      end
    end

    # Parses the attributes Hash for settings values.
    #
    # API-Private: extracted from SettingsSerializer.load_from_record
    # and SettingsSerializer.load_from_hash
    #
    # settings - A Settings to be modified.
    # attrs    - The full Hash attributes that is being loaded.
    #
    # Returns nothing.
    def self.load_subscribed_and_participating_settings(settings, attrs)
      settings.participating_settings << Newsies::HANDLER_WEB   if enabled?(attrs, Newsies::SETTINGS_GROUP_PARTICIPATING, Newsies::HANDLER_WEB)
      settings.participating_settings << Newsies::HANDLER_EMAIL if enabled?(attrs, Newsies::SETTINGS_GROUP_PARTICIPATING, Newsies::HANDLER_EMAIL)
      settings.participating_settings.uniq!

      settings.subscribed_settings << Newsies::HANDLER_WEB   if enabled?(attrs, Newsies::SETTINGS_GROUP_SUBSCRIBED, Newsies::HANDLER_WEB)
      settings.subscribed_settings << Newsies::HANDLER_EMAIL if enabled?(attrs, Newsies::SETTINGS_GROUP_SUBSCRIBED, Newsies::HANDLER_EMAIL)
      settings.subscribed_settings.uniq!
    end

    # API-Private
    #
    # Provided a hash in attrs, it returns whether a certain flag, identified
    # by the group, and the handler; is active.
    #
    # * attrs: A Hash containing the attributes from the NotificationUserSettings
    # active record.
    # * group: Newsies::SETTINGS_GROUP_PARTICIPATING or Newsies::SETTINGS_GROUP_SUBSCRIBED.
    # * handler: Newsies::HANDLER_WEB or Newsies::HANDLER_EMAIL
    #
    def self.enabled?(attrs, group, handler)
      flag = "#{group}_#{handler}"
      attrs[flag]
    end

    # Parses the attributes Hash for emails values.
    #
    # settings - A Settings to be modified.
    # attrs    - The Hash value of the 'emails' key of the attributes Hash.
    #
    # Returns nothing.
    def self.load_emails(settings, emails)
      each_email(emails) do |key, email|
        settings.email(key, email[:email])
      end
    end

    # Yields valid email settings in a consistent manner.  Symbol keys are
    # converted to strings, email Hashes have only the expected keys, etc.
    #
    # emails - A Hash in a similar style to the 'emails' key of the settings
    #          Hash.
    #
    # Yields a String key and a Hash of the email properties.
    # Returns nothing.
    def self.each_email(emails)
      emails.each do |key, email|
        next unless Newsies::Settings::Email.key?(key_s = key.to_s) &&
          email.respond_to?(:symbolize_keys)
        yield key_s, email.symbolize_keys.slice(:email)
      end
    end
  end
end
