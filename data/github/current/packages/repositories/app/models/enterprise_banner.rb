# typed: false
# frozen_string_literal: true

class EnterpriseBanner < ApplicationRecord::Collab
  include Instrumentation::Model

  belongs_to :owner, polymorphic: true
  has_many :enterprise_banner_dismissals
  destroy_dependents_in_background :enterprise_banner_dismissals

  delegate :target_for_conditional_access, to: :owner

  after_commit :handle_metrics, on: [:create, :update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # If changing the max length, also adjust the length of the column in the database
  MAX_MESSAGE_LENGTH = 512

  validates :owner_type,
    presence: true,
    # User is present because orgs are users internally
    inclusion: { in: %w[Repository User Business] }

  validates :message,
    presence: true,
    # If changing the max length, also adjust the length of the column in the database
    length: { maximum: MAX_MESSAGE_LENGTH }

  validate :expires_at_in_future
  validate :expires_or_dismissible

  def expires_at_in_future
    if expires_at && expires_at <= Time.now + 1.minute
      errors.add(:base, "expiration must be a valid date in the future.")
    end
  end

  def expires_or_dismissible
    if expires_at.nil? && dismissible == false
      errors.add(:base, "announcements must either have an expiration date or be dismissible.")
    end
  end

  scope :active, -> { where(expires_at: nil).or(where("expires_at > ?", Time.now.utc)) }

  def self.build_from_form(owner, form_payload)
    expires_at = form_payload[:announcement_expires_at].presence
    new(
      owner: owner,
      message: form_payload[:announcement],
      dismissible: form_payload[:user_dismissible] == "true",
      expires_at: expires_at && Time.parse(expires_at).utc
    )
  end

  def self.user_in_business(user, business)
    return false if business.nil?
    return false if business.billing_manager?(user)

    # users and apps must be members of the business in question to access announcements
    if user.can_have_granular_permissions?
      return false if user.ability_delegate.target&.business&.id != business.id
    else
      return false if !user.businesses.pluck(:id).include?(business.id)
    end

    true
  end

  # TODO is this needed? Does it make more sense as a static method?
  def dismiss(user)
    # No need to throw an error if the banner is not dismissible
    return unless dismissible

    # Performs an upsert to dismiss the banner for the user. Note that the ON DUPLICATE KEY UPDATE syntax will
    # reserve an ID for the new row even if it ends up being a duplicate (and therefore nothing is inserted).
    ApplicationRecord::Collab.connection.insert(Arel.sql(<<-SQL, id: self.id, user_id: user.id))
      INSERT INTO enterprise_banner_dismissals (enterprise_banner_id, user_id)
      VALUES (:id, :user_id)
      ON DUPLICATE KEY UPDATE
        id = id
    SQL
  end

  def upsert_for(owner, actor = nil)
    current_announcement = self.class.find_by(owner: owner)
    transaction do
      # "Reset" dismissals when updating banner
      if current_announcement
        current_announcement.destroy
        instrument(
          :update,
          actor: actor,
          message: message,
          old_message: current_announcement.message,
          dismissibility: dismissible,
          old_dismissibility: current_announcement.dismissible,
          expiry: expires_at&.strftime("%Y-%m-%d"),
          old_expiry: current_announcement.expires_at&.strftime("%Y-%m-%d")
        )
      else
        instrument(:create, actor: actor, message: message, dismissibility: dismissible, expiry: expires_at&.strftime("%Y-%m-%d"))
      end

      save
    end
  end

  def self.clear_for(owner, actor = nil)
    current_announcement = find_by(owner: owner)
    if current_announcement
      current_announcement.destroy
      current_announcement.instrument(:destroy, actor: actor)
    end
  end

  def event_payload
    payload = {
      owner_type: user_facing_owner_type,
      business: owning_business
    }

    case owner_type
    when "Repository"
      payload[:owner] = owner.name_with_display_owner
      payload[:repo] = owner
      payload[:org] = owner.organization if owner.organization
    when "User" # Organization
      payload[:owner] = owner.display_login
      payload[:org] = owner
    when "Business"
      payload[:owner] = owner.name
    end

    payload
  end

  def event_prefix
    "enterprise_announcement"
  end

  def user_facing_owner_type
    case owner_type
    when "Repository"
      "repository"
    when "User"
      "organization"
    when "Business"
      "enterprise"
    end
  end

  def owning_business
    case owner_type
    when "Repository", "User"
      owner.business
    when "Business"
      owner
    end
  end

  def ==(other)
    self.class == other.class && message == other.message && expires_at == other.expires_at && dismissible == other.dismissible
  end

  private

  def handle_metrics
    GlobalInstrumenter.instrument("announcement_banners.publish", {
      announcement_id: id,
      user_facing_owner_type: user_facing_owner_type,
      owner_id: owner.id,
      message_length: message.length,
      expires_at: expires_at,
      user_dismissible: dismissible
    })
  end
end
