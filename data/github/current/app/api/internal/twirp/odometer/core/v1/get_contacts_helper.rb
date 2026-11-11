# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Odometer::Core::V1
  module GetContactsHelper
    extend self

    CPM_TOPIC_ID = "00000000-0000-0000-0000-000000000006"
    OWNER_CONTACT_EMAIL_CAMPAIGN_ID = "owner_contact_email"

    # users: Array of hashes with Users (e.g. enterprise owners, org admins) and their emails
    #  [{ user: <User>, email: <String> }, ...]
    # Returns: Array of Hashes with :email, :contactable, :login, :name, :unsubscribe_url
    def build_contacts_for_users(user_emails)
      emails = user_emails.map { |c| c[:email] }.uniq
      contactability_by_email = fetch_cpm_contactability(emails.first(30)) # CPM API limit of 30 per request

      user_emails.map do |user_data|
        email = user_data[:email]
        user = user_data[:user]
        cpm_info = contactability_by_email[email.downcase] || {}
        {
          email: email,
          contactable: cpm_info[:canContact] || false,
          login: user.login,
          name: user.safe_profile_name,
          unsubscribe_url: cpm_info[:unsubscribeUrl] || ""
        }
      end
    end

    def user_emails(users)
      users.map do |user|
        email = notification_email_for(user)
        { user: user, email: email }
      end
    end

    def notification_email_for(user)
      settings_response = GitHub.newsies.settings(user)
      if settings_response.success?
        settings = settings_response.value!
        notification_email = settings.email(:global)
        return notification_email.address if notification_email&.address.present?
      end
      user.default_notification_email
    rescue StandardError => e
      GitHub.logger.error("Failed to get notification email for user #{user.login}: #{e.message}")
      user.default_notification_email
    end

    def fetch_cpm_contactability(emails)
      return {} if emails.empty?
      cpm_client = Cpm::RestApiClient.new
      response = cpm_client.check_email_contactability(
        emails,
        CPM_TOPIC_ID,
        OWNER_CONTACT_EMAIL_CAMPAIGN_ID
      )
      if response[:has_error]
        GitHub.logger.warn("CPM contactability check failed: #{response[:message]}")
        return {}
      end
      (response[:contacts] || []).index_by { |c| c[:email]&.downcase }
    rescue StandardError => e
      GitHub.logger.error("Error fetching CPM contactability: #{e.message}")
      {}
    end
  end
end
