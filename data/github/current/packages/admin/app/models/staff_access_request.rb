# typed: true
# frozen_string_literal: true

class StaffAccessRequest < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include GitHub::Validations

  validates :requested_by_id, presence: true
  validates :accessible_id,   presence: true
  validates :reason,          presence: true, unicode3: true
  validates :expires_at,      presence: true, follows: :created_at
  validate :requested_by_must_be_staff, on: :create

  belongs_to :requested_by, class_name: "User"
  belongs_to :cancelled_by, class_name: "User"
  belongs_to :denied_by, class_name: "User"
  belongs_to :accessible, polymorphic: true
  has_one :grant, class_name: "StaffAccessGrant"

  after_initialize :calculate_expiry, if: :new_record?
  after_commit :instrument_create, on: :create

  DEFAULT_EXPIRY = 20.days
  REQUEST_NOT_ACTIVE_MESSAGE = "This request is no longer active.".freeze

  class RequestNotActive < StandardError
    def message
      REQUEST_NOT_ACTIVE_MESSAGE
    end
  end

  # Raised if someone is not allowed to accept/deny the request
  class InsufficientAbilities < StandardError
    def initialize(actor, action, subject)
      super "#{actor} isn't allowed to #{action} #{subject}"
    end
  end

  # Accept an active StaffAccessRequest, creating a StaffAccessGrant
  # Retuns the created grant if successful, nil if not.
  def accept(accepting_user)
    raise RequestNotActive unless self.active?
    raise InsufficientAbilities.new(accepting_user, "admin", accessible) unless accessible.adminable_by?(accepting_user)

    if self.grant = StaffAccessGrant.create(granted_by: accepting_user, accessible: accessible, reason: reason)
      instrument :accept, determine_actor(accepting_user)
      self.grant
    end
  end

  def cancel(cancelling_user)
    raise RequestNotActive unless self.active?
    raise InsufficientAbilities.new(cancelling_user, "cancel", self) unless cancelling_user.site_admin?

    self.update!(cancelled_by: cancelling_user, cancelled_at: Time.now)
    instrument :cancel, determine_actor(cancelling_user)
  end

  def deny(denying_user)
    raise RequestNotActive unless self.active?
    raise InsufficientAbilities.new(denying_user, "admin", accessible) unless accessible.adminable_by?(denying_user)

    self.update!(denied_by: denying_user, denied_at: Time.now)
    instrument :deny, determine_actor(denying_user)
  end

  def accepted?
    self.grant.present?
  end

  def cancelled?
    !!cancelled_at
  end

  def denied?
    !!denied_at
  end

  def expired?
    Time.now >= self.expires_at
  end

  def active?
    !(accepted? || cancelled? || denied? || expired?)
  end

  private

  def calculate_expiry
    self.expires_at = Time.zone.now + DEFAULT_EXPIRY
  end

  def requested_by_must_be_staff
    if self.requested_by.present? && !T.must(self.requested_by).site_admin?
      errors.add(:requested_by, "must be a staff member")
    end
  end

  def instrument_create
    instrument :create, determine_actor(requested_by)
  end

  def event_payload
    {
      accessible.event_prefix => accessible,
      :reason => reason,
    }
  end

  def determine_actor(actor)
    if actor.site_admin?
      return GitHub.guarded_audit_log_staff_actor_entry(actor)
    end

    { actor: actor }
  end
end
