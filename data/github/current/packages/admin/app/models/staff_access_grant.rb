# typed: true
# frozen_string_literal: true

class StaffAccessGrant < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include GitHub::Validations

  belongs_to :granted_by, class_name: "User"
  belongs_to :revoked_by, class_name: "User"
  belongs_to :accessible, polymorphic: true
  # rubocop:todo Rails/InverseOf
  belongs_to :request, class_name: "StaffAccessRequest", foreign_key: "staff_access_request_id"
  # rubocop:enable Rails/InverseOf

  validates :accessible, presence: true
  validates :granted_by, presence: true
  validates :reason,     presence: true, unicode3: true
  validates :expires_at, presence: true, follows: :created_at

  after_initialize :calculate_expiry, if: :new_record?
  after_commit :instrument_create, on: :create

  DEFAULT_EXPIRY = 5.days

  # Raised if someone is not allowed to accept/deny the request
  class InsufficientAbilities < StandardError
    def initialize(actor, action, subject)
      super "#{actor} isn't allowed to #{action} #{subject}"
    end
  end

  class GrantNotActive < StandardError; end

  def revoke(revoking_user)
    raise GrantNotActive unless self.active?
    raise InsufficientAbilities.new(revoking_user, "admin", accessible) unless accessible.adminable_by?(revoking_user)

    self.update!(revoked_by: revoking_user, revoked_at: Time.now)
    instrument :revoke, { actor: revoking_user }
  end

  def expired?
    Time.now >= self.expires_at
  end

  def revoked?
    !!revoked_at
  end

  def active?
    !(expired? || revoked?)
  end

  private

  def calculate_expiry
    self.expires_at = Time.zone.now + DEFAULT_EXPIRY
  end

  def event_payload
    {
      accessible.event_prefix => accessible,
      :reason => reason,
      :staff_access_request => request,
    }
  end

  def instrument_create
    instrument :create, { actor: granted_by }
  end
end
