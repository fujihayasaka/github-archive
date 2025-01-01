# typed: strict
# frozen_string_literal: true

class Licensing::BundledLicenseAssignment < ApplicationRecord::Domain::Billing
  include GitHub::Memoizer
  include Instrumentation::Model

  belongs_to :business, optional: true
  belongs_to :user, optional: true

  validates :enterprise_agreement_number, presence: true
  validates :email, presence: true, length: { maximum: 320 }
  validates :subscription_id,
    presence: true,
    uniqueness: { case_sensitive: false, conditions: -> { nonrevoked }, unless: :revoked? }
  validates :revoked, inclusion: { in: [false, true] }

  before_save :handle_user_changed, if: :will_save_change_to_user_id?
  before_save :handle_business_changed, if: :will_save_change_to_business_id?
  before_save :handle_revoke_changed, if: :will_save_change_to_revoked?
  after_commit :handle_updates, on: [:create, :update]
  after_commit :send_vss_status, on: [:create, :update]
  after_create_commit :instrument_creation

  scope :assigned_user, -> { where.not(user_id: nil) }
  scope :unassigned_user, -> { where(user_id: nil) }

  scope :assigned_business, -> { where.not(business: nil) }
  scope :unassigned_business, -> { where(business: nil) }

  scope :for_enterprise_agreement, -> (agreement_number) { where("enterprise_agreement_number = ?", agreement_number) }
  scope :nonrevoked,  -> { where(revoked: false) }

  # Scope that returns only assignments where email matches the given query.
  #
  # Should only be used for filtering existing well scoped queries. For example,
  # filtering assignments already belonging to a specific Business.
  #
  # query - String containing the query.
  #
  # Returns ActiveRecord::Relation.
  scope :for_query, ->(query) {
    safe_query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    return scoped unless safe_query.present?

    where <<-SQL, query: "%#{safe_query}%"
      bundled_license_assignments.email LIKE :query
    SQL
  }

  sig { returns(T::Boolean) }
  memoize def assigned_user?
    user_id? && user.present?
  end

  sig { returns(T::Boolean) }
  def assigned_business?
    business_id?
  end

  sig { params(email: T.nilable(String)).returns(T.self_type) }
  def revoke!(email: nil)
    # Same email means a non anonymized revoke
    if email == self.email || email.nil?
      update!(revoked: true)
    else
      update!(revoked: true, email: email, user_id: nil)
    end
  end

  sig { returns(::Business::PendingInvitation) }
  def to_pending_invitation
    Business::PendingInvitation.from_bundled_license_assignment(self)
  end

  sig { void }
  def attempt_to_assign_user_from_business
    return unless business_id?

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_later(assignment: self)
  end

  private

  sig { returns(String) }
  def bundled_license_assignment_creation_email_key
    "bundled_license_assignment_creation_email_#{id}"
  end

  # Send email when assignment has a business set to the email on the assignment
  sig { void }
  def send_creation_email
    business = self.business
    # check for business, flag, and that we have not sent this email yet
    return unless business &&
      !Billing::Kv.store.exists(bundled_license_assignment_creation_email_key).value!

    # create the key value store to mark email as already sent
    Billing::Kv.store.setnx(bundled_license_assignment_creation_email_key, business.id.to_s)

    # send the email
    BillingNotificationsMailer.bundled_license_assignment_created(self).deliver_later
  end

  sig { void }
  def handle_revoke_changed
    if revoked?
      self.revoked_at = Time.current
      @newly_revoked = T.let(true, T.nilable(T::Boolean))
    else
      self.revoked_at = nil
    end
  end

  sig { void }
  def handle_business_changed
    if business_id?
      @new_business_assigned = T.let(true, T.nilable(T::Boolean))
      self.assigned_business_at = Time.current
    else
      self.assigned_business_at = nil
    end
  end

  sig { void }
  def handle_user_changed
    old_id, new_id = user_id_change_to_be_saved
    @user_unassigned = T.let(User.find_by(id: old_id), T.nilable(User)) if old_id

    if new_id
      self.assigned_user_at = Time.current
      @new_user_assigned = T.let(true, T.nilable(T::Boolean))
    else
      self.assigned_user_at = nil
    end
  end

  sig { void }
  def handle_updates
    if @newly_revoked
      @newly_revoked = false
      instrument_revoke
    end

    if @user_unassigned
      instrument_user_unassignment
      @user_unassigned = nil
    end

    if @new_user_assigned
      @new_user_assigned = false
      instrument_user_assignment
    end

    if @new_business_assigned
      @new_business_assigned = false
      attempt_to_assign_user_from_business
      instrument_business_assignment
      send_creation_email unless GitHub.flipper[:skip_bundled_license_assignment_email].enabled?(business)
    end

    business&.update_license_usage if business_id?
  end

  sig { returns(String) }
  def event_prefix
    "bundled_license_assignment"
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def event_payload
    {
      bundled_license_assignment: self,
      email: email,
      enterprise_agreement_number: enterprise_agreement_number,
      subscription_id: subscription_id,
      business: business
    }.compact
  end

  sig { void }
  def instrument_creation
    instrument :create
  end

  sig { void }
  def instrument_revoke
    instrument :revoke, revoked: revoked
  end

  sig { void }
  def instrument_user_assignment
    instrument :assigned_user, user: user
  end

  sig { void }
  def instrument_user_unassignment
    instrument :unassigned_user, user: @user_unassigned
  end

  sig { void }
  def instrument_business_assignment
    instrument :assigned_business, business_id: business_id if business_id?
  end

  sig { void }
  def send_vss_status
    Licensing::SendVssStatusMessageJob.perform_later(assignment: self)
  end
end
