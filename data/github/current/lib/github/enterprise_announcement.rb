# typed: true
# frozen_string_literal: true

require "github/config/mysql"
GitHub.load_activerecord
require "github/config/kv"
require "github/enterprise_accounts/kv"

# Encapsulates logic for managing the GHES global announcement banner.
module GitHub
  module EnterpriseAnnouncement
    ANNOUNCEMENT_KEY = "enterprise:announcement"

    class AnnouncementDetails
      # String: UUID of the announcement
      attr_accessor :uuid

      # String: The announcement text in GitHub Flavored Markdown
      attr_accessor :text

      # String: The announcement text as HTML
      attr_accessor :text_html

      # Boolean: Whether the announcement is dismissible by the user
      attr_accessor :user_dismissible

      # Time: The time at which the announcement expires
      attr_accessor :expires_at

      def initialize(uuid: nil, text: nil, user_dismissible: nil, expires_at: nil)
        @uuid = uuid
        @text = text
        @user_dismissible = user_dismissible
        @expires_at = expires_at
      end

      def ==(other)
        (@text == other[:text]) &&
          (@user_dismissible == other[:user_dismissible]) &&
          (@expires_at == other[:expires_at])
      end
    end

    class SetAnnouncementResult
      attr_accessor :errors

      def initialize(errors: [])
        @errors = errors
      end

      def success?
        errors.empty?
      end
    end

    # Public: Get the current announcement.
    #
    # Returns GitHub::EnterpriseAnnouncement::AnnouncementDetails.
    def self.get_announcement
      announcement = EnterpriseAccounts::KV.store.get(ANNOUNCEMENT_KEY).value { nil }

      return AnnouncementDetails.new unless announcement.present?

      # Parse JSON announcement, e.g. "{\"uuid\":\"blah-uuid\",\"text\":\"an important announcement\",\"user_dismissible\":false}"
      if is_json?(announcement)
        uuid, text, user_dismissible = GitHub::JSON
        .parse(announcement, { symbolize_names: true })
        .values_at(:uuid, :text, :user_dismissible)
      # Parse legacy announcement, e.g. "an important announcement"
      else
        text = announcement
      end

      # Force UTF-8 encoding so that Comments::PreviewableCommentFormComponent can handle the value
      AnnouncementDetails.new \
        uuid: uuid,
        text: text.present? ? text.dup.force_encoding("utf-8").scrub! : nil,
        user_dismissible: user_dismissible,
        expires_at: EnterpriseAccounts::KV.store.ttl(ANNOUNCEMENT_KEY).value { nil }
    end

    # Public: Set the announcement, optionally providing an expiry time and dismissible status.
    #
    # announcement - Required. String containing the announcement markdown.
    # expires_at   - Optional. String representing the time in the future at
    #                which the announcement should expire in format YYYY-MM-DD.
    # user_dismissible   - Optional. Boolean indicating whether the announcement
    #                      banner should be dismissible by each user.
    #
    # Returns GitHub::EnterpriseAnnouncement::SetAnnouncementResult.
    def self.set_announcement(announcement:, expires_at: nil, user_dismissible: false)
      errors = []

      if announcement.blank?
        errors << "Announcement cannot be blank"
        return SetAnnouncementResult.new errors: errors
      end

      if get_announcement == { text: announcement, expires_at: expires_at, user_dismissible: user_dismissible }
        return SetAnnouncementResult.new
      end

      announcement_json = GitHub::JSON.encode({
        uuid: SecureRandom.uuid,
        text: announcement,
        user_dismissible: user_dismissible
      })

      if expires_at.present?
        if valid_expires_at?(expires_at)

          EnterpriseAccounts::KV.store.set(
            ANNOUNCEMENT_KEY,
            announcement_json,
            expires: Date.parse(expires_at.to_s).to_time
          )
        else
          errors << "Announcement expiry date must be a valid date in the future"
        end
      else
        EnterpriseAccounts::KV.store.set(ANNOUNCEMENT_KEY, announcement_json)
      end

      SetAnnouncementResult.new errors: errors
    end

    # Public: Clear the current announcement.
    #
    # Returns nothing.
    def self.clear_announcement
      EnterpriseAccounts::KV.store.del(ANNOUNCEMENT_KEY)
    end

    # Internal: Check whether a given expires_at value is valid for an announcement.
    #
    # expires_at - String containing the expiry date in the format YYYY-MM-DD.
    #
    # Returns Boolean.
    def self.valid_expires_at?(expires_at)
      Date.parse(expires_at.to_s).to_time.future?
    rescue ArgumentError
      false
    end

    def self.is_json?(announcement)
      announcement.is_a?(String) && announcement.starts_with?("{") && announcement.ends_with?("}")
    end
  end
end
