# typed: true
# frozen_string_literal: true

class UserStatus < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include GitHub::Validations

  MESSAGE_MAX_LENGTH = 80

  PREDEFINED_STATUSES = {
    "palm_tree" => "On vacation",
    "face_with_thermometer" => "Out sick",
    "house" => "Working from home",
    "dart" => "Focusing",
  }.freeze

  belongs_to :user
  belongs_to :organization

  after_commit :instrument_update, :log_status_change_to_hydro, on: [:create, :update]
  after_commit :instrument_destroy, :log_status_clear_to_hydro, on: [:destroy]

  extend GitHub::Encoding
  force_utf8_encoding :message, :emoji

  validates :user, presence: true
  validates :user_id, uniqueness: true
  validates :message, length: { maximum: MESSAGE_MAX_LENGTH }, allow_blank: true
  validates :emoji, allow_blank: true, single_emoji: true, allowed_emoji: true
  validate :user_belongs_to_organization
  validate :emoji_or_message_exists

  scope :for_org, ->(org) { where(organization_id: org) }

  scope :for_org_or_public, ->(org) {
    where("user_statuses.organization_id = ? OR user_statuses.organization_id IS NULL", org)
  }

  scope :active, -> {
    where("user_statuses.expires_at > ? OR user_statuses.expires_at IS NULL", Time.current)
  }

  def self.blocked_emoji?(value)
    GitHub::Validations::AllowedEmojiValidator.blocked_emoji?(value)
  end

  # Public: Check if the given emoji and message constitute a valid status.
  #
  # emoji - String or nil
  # message - String or nil
  #
  # Returns a Boolean.
  def self.valid_emoji_and_message?(emoji, message)
    status = UserStatus.new
    status.emoji = emoji.presence
    status.message = message.presence
    status.validate

    # The missing user should be the only thing wrong with the status
    status.errors.attribute_names == [:user]
  end

  # Public: Update a user's status.
  #
  # user - User instance
  # emoji - optional native or colon-style emoji; String or nil
  # message - optional message for the user's current activity; String or nil
  # org - optional Organization to limit the visibility of the status; the user must belong
  #       to this org or it will be ignored
  # limited_availability - whether this status indicates you're not fully available
  # expires_at - optional Datetime; the status will not be shown after this DateTime
  #
  # Returns a UserStatus or nil.
  sig do
    params(
      user: User,
      emoji: T.nilable(String),
      message: T.nilable(String),
      org: T.nilable(Organization),
      limited_availability: T::Boolean,
      expires_at: T.nilable(Time),
    ).returns(T.nilable(UserStatus))
  end
  def self.set_for(user, emoji:, message:, org: nil, limited_availability: false, expires_at: nil)
    if emoji.blank? && message.blank?
      # Wipe existing status
      existing_status = user.user_status
      return if existing_status.nil? || existing_status.destroy
    end

    emoji_value = "NULL"
    message_value = "NULL"
    org_id_value = "NULL"
    expires_at_value = "NULL"
    query_args = { user_id: user.id, limited_availability: limited_availability }

    if emoji.present?
      query_args[:emoji] = GitHub::SQL::ArelLiterals.binary(emoji)
      emoji_value = ":emoji"
    end

    if message.present?
      query_args[:message] = GitHub::SQL::ArelLiterals.binary(message)
      message_value = ":message"
    end

    if org && org.member?(user)
      query_args[:org_id] = org.id
      org_id_value = ":org_id"
    end

    if expires_at.present?
      query_args[:expires_at] = expires_at.to_datetime
      expires_at_value = ":expires_at"
    end

    return user.user_status unless valid_emoji_and_message?(emoji, message)

    query = %Q(
      INSERT INTO user_statuses (
        user_id,
        emoji,
        message,
        organization_id,
        expires_at,
        limited_availability,
        created_at,
        updated_at
      ) VALUES (
        :user_id,
        #{emoji_value},
        #{message_value},
        #{org_id_value},
        #{expires_at_value},
        :limited_availability,
        NOW(),
        NOW()
      ) ON DUPLICATE KEY UPDATE
        emoji = VALUES(emoji),
        message = VALUES(message),
        expires_at = VALUES(expires_at),
        limited_availability = VALUES(limited_availability),
        organization_id = VALUES(organization_id),
        updated_at = VALUES(updated_at)
    )

    self.connection.insert(Arel.sql(query, **query_args))

    status = T.must(user.user_status).reload
    status.instrument_update
    instrument_status_change(status, emoji: emoji, message: message)
    status
  end

  # Public: Returns HTML to render the emoji, or nil.
  def emoji_html
    if emoji.present?
      context = T.let({ base_url: GitHub.url }, T::Hash[Symbol, String])
      GitHub::Goomba::ProfileBioPipeline.to_html(emoji, context)
    end
  end

  def async_message_html(viewer: nil, link_mentions: true)
    return Promise.resolve(nil) if message.blank?

    async_organization.then do |org|
      context = T.let({ base_url: GitHub.url, organization: org, current_user: viewer }, T::Hash[Symbol, T.untyped])
      pipeline = if link_mentions
        GitHub::Goomba::ProfileBioPipeline
      else
        GitHub::Goomba::PlainUserStatusPipeline
      end
      pipeline.async_to_html(message, context)
    end
  end

  # Public: Returns HTML to render the message, or nil.
  #
  # viewer - the current user or nil
  # link_mentions - should users, orgs, and teams that are @-mentioned be turned into links
  #
  # Returns a String or nil.
  def message_html(viewer: nil, link_mentions: true)
    async_message_html(viewer: viewer, link_mentions: link_mentions).sync
  end

  def self.instrument_status_change(user_status, emoji: nil, message: nil)
    GlobalInstrumenter.instrument("user.change_status", user: user_status.user, emoji: emoji,
                                  message: message, user_status: user_status)
  end

  def async_readable_by?(viewer)
    async_user.then do |user|
      if user == viewer
        true # can always view your own status
      elsif T.must(user).hide_from_user?(viewer)
        false # user is spammy or suspended, so don't show their status
      else
        async_organization.then do |org|
          if org
            org.member_or_can_view_members?(viewer) # other members of the org can see the status
          else
            true # public status
          end
        end
      end
    end
  end

  def event_prefix
    :user_status
  end

  def event_context(prefix: event_prefix)
    {
      prefix => to_s,
      "#{prefix}_id".to_sym => id,
    }
  end

  def event_payload
    {
      event_prefix => self,
      :emoji => emoji,
      :message => message,
      :user => user,
      :org => organization,
      :limited_availability => limited_availability,
      :expires_at => expires_at,
    }
  end

  def to_s
    [emoji, message].compact.join(" ").presence
  end

  def instrument_update
    instrument :update
  end

  # Public: Check if this status has past its expiration date.
  def expired?
    expiration = expires_at
    return false unless expiration.present?
    expiration <= Time.current
  end

  private

  def instrument_destroy
    instrument :destroy
  end

  def log_status_change_to_hydro
    self.class.instrument_status_change(self, emoji: emoji, message: message)
  end

  def log_status_clear_to_hydro
    self.class.instrument_status_change(self, emoji: nil, message: nil)
  end

  def emoji_or_message_exists
    if emoji.blank? && message.blank?
      errors.add(:base, "Either an emoji or a message is required.")
    end
  end

  def user_belongs_to_organization
    this_org = organization
    this_user = user
    return unless this_user.present? && this_org.present?

    unless this_org.member?(this_user)
      errors.add(:organization, "must be an organization #{this_user} belongs to")
    end
  end
end
