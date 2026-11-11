# typed: true
# frozen_string_literal: true

class TwoFactorRecoveryRequest < ApplicationRecord::Domain::UsersCollab
  include GH::Associations::BatchMethodAdapters
  include Instrumentation::Model

  ABORT_TOKEN_EXPIRY = 1.week
  ABORT_TOKEN_SCOPE = "AbortAccountRecoveryRequest"

  COMPLETE_TOKEN_EXPIRY = 4.days
  COMPLETE_TOKEN_SCOPE = "CompleteAccountRecoveryRequest"

  RECOVERY_DISPUTE_QUERY = "request_completed_at <= ?
    AND staff_review_requested_at IS NULL
    AND approved_at IS NULL
    AND declined_at IS NULL"

  # skipping GraphQL support for now until this is more baked
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  destroy_in_background_with :user
  belongs_to :requesting_device, class_name: "AuthenticatedDevice"
  belongs_to :authenticated_device, optional: true
  belongs_to :oauth_access, optional: true
  belongs_to_domain(:oauth_access, foreign_key: :oauth_access_id, ar_relation: true,
    return_type: T.nilable(OauthAccessTokens::IOauthAccess)) do |oauth_access_ids|
    OauthAccessTokens.domain.by_ids(oauth_access_ids)
  end
  belongs_to :public_key, optional: true

  belongs_to :reviewer, class_name: "User", required: false

  validates_presence_of :user
  validates_presence_of :requesting_device

  validate :requesting_device_is_for_same_user

  validate :authenticated_device_is_verified, on: [:update]
  validate :authenticated_device_is_for_same_user

  validate :public_key_is_for_same_user

  validate :is_personal_access_token, :token_is_for_same_user

  validate :staff_member_is_approver

  scope :ready_for_review, -> { where([RECOVERY_DISPUTE_QUERY, self.one_business_day_ago(Time.now)]).order(:request_completed_at).preload(:user) }

  def event_payload
    {
      :user => user,
      event_prefix => self,
    }
  end

  def event_prefix
    :two_factor_account_recovery
  end

  after_create_commit :instrument_start_on_create

  after_commit :instrument_completion, on: :update, if: :request_completed_at_previously_changed?

  # Instrument the .start event for existing requests that were not freshly
  # created in this process (e.g. reused from a prior session). Guards against
  # duplicate events within the same object lifecycle.
  def instrument_start_if_needed
    return if @start_instrumented

    instrument :start, requesting_device: requesting_device
    @start_instrumented = true
  end

  def instrument_completion
    instrument :complete
    @completion_instrumented = true
  end

  # Explicitly instrument .complete when the model callback may not fire
  # (e.g. request_completed_at was already set on a double-submit).
  def instrument_completion_if_needed
    return if @completion_instrumented

    instrument_completion
  end

  def instrument_abort
    instrument :abort
    GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
      action_type: :REQUEST_ABORTED,
      user: user,
    )
  end

  def instrument_two_factor_destroy
    instrument :two_factor_destroy
  end

  def instrument_ignore
    instrument :ignore
  end

  def instrument_start_on_create
    instrument :start, requesting_device: requesting_device
    @start_instrumented = true

    GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
      action_type: :REQUEST_STARTED,
      user: user,
    )
  end

  # the user flow should be restricted to this method to prevent multi-device
  # access to the flow (or limited access from an external source with the token)
  def self.find_request(user, device)
    self.where(
        user_id: user.id,
        requesting_device: device,
        declined_at: nil,
      ).first
  end

  # Amount of time to wait before sending Zendesk ticket for verification
  def self.one_business_day_ago(date)
    # If it's Tuesday-Friday, we can consider requests that were completed only 24hrs ago.
    return 24.hours.ago if date.wday >= 2 && date.wday <= 5

    # Otherwise, we need to wait until the following Monday.
    72.hours.ago
  end

  # the staff flow should look for the most recent completed request for the user
  # and factor in whether the request was approved or declined
  def self.find_for_staff_review(user)
    user.two_factor_recovery_requests
        .where.not(request_completed_at: nil)
        .order(updated_at: :desc)
        .first
  end

  def mark_as_complete!
    self.request_completed_at = Time.current
    save!
  end

  def self.generate_one_time_password
    6.times.map { SecureRandom.random_number(10) }.join
  end

  def generate_abort_token
    GitHub::Authentication::SignedAuthToken.generate(
      user: user,
      scope: ABORT_TOKEN_SCOPE,
      expires: ABORT_TOKEN_EXPIRY.from_now,
    )
  end

  def self.verify_abort_token(token)
    GitHub::Authentication::SignedAuthToken.verify(
      token: token,
      scope: ABORT_TOKEN_SCOPE,
    )
  end

  def generate_complete_token
    GitHub::Authentication::SignedAuthToken.generate(
      user: user,
      scope: COMPLETE_TOKEN_SCOPE,
      expires: COMPLETE_TOKEN_EXPIRY.from_now,
    )
  end

  def self.verify_complete_token(token)
    GitHub::Authentication::SignedAuthToken.verify(
      token: token,
      scope: COMPLETE_TOKEN_SCOPE,
    )
  end

  def verify_otp
    self.otp_verified = true
    self.save
  end

  def unverify_otp
    self.otp_verified = false
    self.save
  end

  def approve(user, approved_emails = nil)
    if self.update!(reviewer: user, approved_at: Time.now)
      abort_token = self.generate_abort_token
      complete_token = self.generate_complete_token

      AccountRecoveryMailer.request_approved_by_staff(self.user, self.id, abort_token, complete_token, approved_emails).deliver_later
    end
  end

  def approved?
    request_completed_by_user? && staff_has_completed_review? && approved_at.present?
  end

  def requesting_device_is_for_same_user
    return unless user.present?
    return unless requesting_device.present?

    if user != requesting_device&.user
      errors.add(:requesting_device, "Requesting device belongs to user not associated with this record")
    end
  end

  def authenticated_device_is_for_same_user
    return unless authenticated_device.present?
    if user != authenticated_device&.user
      errors.add(:authenticated_device, "Authenticated device belongs to user not associated with this record")
    end
  end

  def public_key_is_for_same_user
    return unless public_key.present?
    if user != public_key&.user
      errors.add(:public_key, "Public key belongs to user not associated with this record")
    end
  end

  def token_is_for_same_user
    return if oauth_access.nil?
    if user != oauth_access&.user
      errors.add(:oauth_access, "Access token belongs to user not associated with this record")
    end
  end

  def authenticated_device_is_verified
    return unless authenticated_device.present?
    if !authenticated_device&.approved_at.present?
      if approved_at.present?
        # We don't allow the request to be approved by staff while we have an associated, unverified
        # authenticated_device.  However, we should still allow other updates so the scheduled notifier job can mark
        # them for review by support.
        errors.add(:authenticated_device, "Authenticated device that is unverified cannot be used")
      end
    end
  end

  def is_personal_access_token
    return if oauth_access.nil?
    errors.add(:oauth_access, "Access token is not a personal access token") if !oauth_access&.personal_access_token?
    errors.add(:oauth_access, "Access token is missing required 'repo' scope") if !oauth_access&.scopes&.include?("repo")
  end

  def staff_member_is_approver
    return if reviewer.nil?
    errors.add(:reviewer, "Site admin is only type of user permitted to approve lockout request") if !reviewer&.site_admin? && !reviewer&.ghost?
  end

  def secondary_evidence_method
    return "Authenticated device" if authenticated_device_id.present?
    return "Public key" if public_key_id.present?
    return "Personal access token" if oauth_access_id.present?

    nil
  end

  def secondary_evidence_identifier
    return authenticated_device&.display_name if authenticated_device.present?
    return public_key&.title if public_key.present?
    return oauth_access&.description unless oauth_access.nil?

    nil
  end

  def review_state
    return :reviewed_by_staff if !reviewer.nil? && approved_at.present?
    return :reviewed_by_staff if !reviewer.nil? && declined_at.present?
    return :evidence_missing if request_completed_by_user? && !secondary_evidence_present?
    return :ready_for_review if request_completed_by_user?

    :incomplete
  end

  def hydro_evidence_type
    return :DEVICE if authenticated_device.present?
    return :SSH_KEY if public_key.present?
    return :PERSONAL_ACCESS_TOKEN unless oauth_access.nil?

    :EVIDENCE_TYPE_UNKNOWN
  end

  private

  def request_completed_by_user?
    otp_verified? && secondary_evidence_provided?
  end

  def staff_has_completed_review?
    return true if !reviewer.nil? && approved_at.present?
    return true if !reviewer.nil? && declined_at.present?

    false
  end

  # this method is checking that the associated evidence was populated, rather
  # than the entity exists on the related table.
  def secondary_evidence_provided?
    return true if authenticated_device_id.present?
    return true if public_key_id.present?
    return true if oauth_access_id.present?

    false
  end

  def secondary_evidence_present?
    return true if authenticated_device_id.present? && authenticated_device.present? && authenticated_device&.approved_at.present?
    return true if public_key_id.present? && public_key.present?
    return true if oauth_access_id.present? && !oauth_access.nil?

    false
  end
end
