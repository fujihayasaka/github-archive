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
  after_commit :emit_hydro_events, on: [:create, :update]
  after_commit :send_vss_status, on: [:create, :update]
  after_create_commit :instrument_creation

  scope :assigned_user, -> { where.not(user_id: nil) }
  scope :unassigned_user, -> { where(user_id: nil) }

  scope :assigned_business, -> { where.not(business: nil) }
  scope :unassigned_business, -> { where(business: nil) }

  scope :for_enterprise_agreement, -> (agreement_number) { where("enterprise_agreement_number = ?", agreement_number) }
  scope :with_subscription, -> (subscription_id) { where(subscription_id: subscription_id) }
  scope :nonrevoked, -> { where(revoked: false) }

  scope :not_manual_match,  -> { where("manual_match = false OR user_id IS NULL") }

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
    if email == self.email || email.nil?
      update!(revoked: true)
    end
  end

  sig { params(email: T.nilable(String)).returns(T.self_type) }
  def revoke_anonymized!(email: nil)
    update!(revoked: true, email:, user_id: nil, manual_match: false, manual_match_at: nil)
  end

  # Unassigns the user from this BLA and resets manual match fields.
  # Takes an optional reason parameter to handle different unassignment scenarios.
  # Triggers appropriate hydro events based on the reason.
  sig { params(reason: T.nilable(Symbol)).returns(T::Boolean) }
  def unassign!(reason: nil)
    if reason == :suspension
      @is_unassign_suspension = T.let(true, T.nilable(TrueClass))
    end

    # ensure update-related callbacks on the model are triggered
    # (ie. creates audit logs)
    update!(
      user_id: nil,
      manual_match: false,
      manual_match_at: nil
    )
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

  sig { returns(T::Boolean) }
  def set_user_by_verified_emails
    return false if revoked?
    business = self.business

    return false if business.nil?

    new_user = nil
    if business.enterprise_managed?
      business_user_account = business.dotcom_users_from_emails([business.add_emu_shortcode_to_emails(email)]).values.first
      if business_user_account&.user
        new_user = business_user_account&.user
      else
        return false unless business.external_provider_enabled?
        new_user = business.external_provider&.external_identities&.by_scim_username(email)&.first&.user
      end
    else
      business_user_account = business.dotcom_users_from_emails([email]).values.first
      new_user = business_user_account&.user
    end

    # Only set the user if there is a match when metered, we don't want to remove an already matched user if there is no longer a match so we don't start billing because of a matching issue.
    if ((!business.metered_plan? && self.manual_match == false && FeatureFlag.vexi.enabled?(:allow_revoke_for_volume, default: false)) || new_user) && new_user&.id != user_id
      self.user_id = new_user&.id
      self.manual_match = false
      self.manual_match_at = nil

      if FeatureFlag.vexi.enabled?(:allow_revoke_for_volume, default: false)
        if new_user&.id.present?
          business.bundled_license_assignments.where.not(id: self.id).nonrevoked.where(user_id: new_user.id).each do |other_assignment|
            other_assignment.unassign!
          end
        end
      end

      true
    else
      false
    end
  end

  private

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

    if manual_match?
      self.manual_match_at = Time.current
    else
      self.manual_match_at = nil
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
      business: business,
      email: email,
      identity: identity,
      enterprise_agreement_number: enterprise_agreement_number,
      subscription_id: subscription_id,
      manual_match: manual_match,
      manual_match_at: manual_match_at,
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

  sig { void }
  def emit_hydro_events
    return unless previous_changes.any?

    if previous_changes.key?("user_id")
      old_user_id, new_user_id = previous_changes["user_id"]

      if old_user_id.present? && new_user_id.present?
        emit_association_changed_event(:USER_REASSIGNED, business: business, user_id: new_user_id, previous_user_id: old_user_id)
      elsif new_user_id.present?
        emit_association_changed_event(:USER_ASSIGNED, business: business, user_id: new_user_id)
      elsif old_user_id.present?
        unassign_change_type = @is_unassign_suspension ? :USER_UNASSIGNED_SUSPENDED : :USER_UNASSIGNED
        emit_association_changed_event(unassign_change_type, business: business, user_id: nil, previous_user_id: old_user_id)
        @is_unassign_suspension = nil # Reset after use
      end
    end

    if previous_changes.key?("business_id")
      old_business_id, new_business_id = previous_changes["business_id"]

      if new_business_id.present?
        emit_association_changed_event(:BUSINESS_ASSOCIATED, business: business, user_id: user_id)
      elsif old_business_id.present?
        emit_association_changed_event(:BUSINESS_DISASSOCIATED, business: nil, user_id: user_id)
      end
    end

    if previous_changes.key?("revoked")
      _, new_revoked = previous_changes["revoked"]

      if new_revoked
        emit_association_changed_event(:REVOKED, business: business, user_id: user_id)
      end
    end
  end

  sig { params(change_type: T.untyped, business: T.untyped, user_id: T.nilable(Integer), previous_user_id: T.nilable(Integer)).void }
  def emit_association_changed_event(change_type, business:, user_id:, previous_user_id: nil)
    GlobalInstrumenter.instrument("licensing.bundled_license_assignment_association_changed", {
      change_type: change_type,
      subscription_id: subscription_id,
      business: business,
      user_id: user_id,
      previous_user_id: previous_user_id
    })
  end
end
