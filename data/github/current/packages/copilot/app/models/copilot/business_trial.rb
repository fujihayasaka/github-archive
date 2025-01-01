# typed: strict
# frozen_string_literal: true

module Copilot
  class BusinessTrial < ApplicationRecord::Copilot
    include Copilot::Helpers
    include ::Instrumentation::Model

    ACTIVE_STATES = T.let(%w[recently_started half_over nearly_over final_day extended].freeze, T::Array[String])
    ONGOING_STATES = T.let((ACTIVE_STATES + %w[pending]).freeze, T::Array[String])

    # States of Copilot Business trials that are eligible to be converted to Copilot Enterprise trials
    CONVERTIBLE_TO_CE_STATES = T.let(%w[canceled expired upgraded].freeze, T::Array[String])

    INACTIVE_DATE = T.let(Date.new(9999, 12, 31), Date)

    self.table_name = "copilot_business_trials"
    self.strict_loading_by_default = true

    belongs_to :trialable, polymorphic: true, strict_loading: false
    # rubocop:todo Rails/InverseOf
    belongs_to :managing_user, class_name: "::User", foreign_key: "managing_user_id", strict_loading: false
    # rubocop:enable Rails/InverseOf

    validates :ends_at, presence: true
    validates :managing_user, presence: true
    validates :started_at, presence: true
    validates :trial_length, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :trialable, presence: true

    validate :trialable_must_be_organization # TODO: see if they want trials for Enterprise Teams
    validate :trialable_must_be_unique
    validate :trialable_must_not_be_standalone_org, on: [:create, :update], if: :copilot_plan_enterprise?
    validate :trialable_must_be_eligible_for_copilot_enterprise,
             :trialable_must_be_billable,
             on: :create,
             if: :copilot_plan_enterprise?
    validate :ends_at_must_be_after_started_at

    scope :active, -> { where(state: ACTIVE_STATES) }
    scope :ongoing, -> { where(state: ONGOING_STATES) }
    scope :for_organization_ids, -> (organization_ids) do
      where(trialable_id: organization_ids, trialable_type: "Organization")
    end

    enum :state, {
      pending: 0,
      recently_started: 1,
      half_over: 2,
      nearly_over: 3,
      final_day: 4,
      upgraded: 5,
      expired: 6,
      canceled: 7,
      extended: 8,
    }, default: :pending

    # Tracks whether the trial is for the Copilot Business or Copilot Enterprise plan.
    # Copilot Business is the default.
    enum :copilot_plan, {
      business: 0,
      enterprise: 1,
    }, prefix: true

    after_create :notify_admin_of_trial_creation
    after_commit :on_state_change, on: :update, if: :saved_change_to_state?

    sig { params(organization: ::Organization).returns(T.nilable(Copilot::BusinessTrial)) }
    def self.for_organization(organization)
      where(trialable_id: organization.id, trialable_type: "Organization").first
    end

    sig { params(organization_id: Integer).returns(T.nilable(Copilot::BusinessTrial)) }
    def self.for_organization_id(organization_id)
      where(trialable_id: organization_id, trialable_type: "Organization").first
    end

    sig { params(org: ::Organization, desired_copilot_plan: String).returns(T::Boolean) }
    def self.existing_trial_in_org_has_different_plan?(org, desired_copilot_plan)
      return false if org.business.nil?
      existing_trial = Copilot::Business.new(T.must(org.business)).ongoing_organization_trials.first
      return false if existing_trial.nil?

      existing_trial.copilot_plan != desired_copilot_plan
    end

    sig do
      params(
        organization: ::Organization,
        managing_user: ::User,
        trial_length: Integer,
        copilot_plan: String,
      ).returns(Copilot::BusinessTrial)
    end
    def self.create_trial!(organization, managing_user, trial_length: 30, copilot_plan: "business")
      trial = Copilot::BusinessTrial.create!(
        ends_at: INACTIVE_DATE,         # ends_at is based on the date that the org admin starts the trial
        managing_user: managing_user,   # staff user who created the trial
        started_at: INACTIVE_DATE,      # started_at is the date that the org admin creates the first seat assignment
        trial_length: trial_length,     # number of days granted to the org (default: 30)
        trialable_id: organization.id,  # the org that is trying copilot,
        trialable_type: "Organization",
        copilot_plan: copilot_plan,
      )

      # if the organization already seat assignments, we need to start the trial now
      if Copilot::SeatAssignment.for_organization(organization).any?
        trial.start_trial! if trial.startable?
      end
      trial
    end

    sig { returns(T::Boolean) }
    def start_trial!
      GitHub.logger.info(
        "Starting business trial",
        "gh.copilot.business_trial.id" => id,
      )
      result = update!(started_at: Date.current, ends_at: Date.current + trial_length.days, state: :recently_started)
      if result
        Copilot::Instrumenter.instrument_copilot_business_trial_started(trialable.admins.first, self)
        return true
      end
      false
    end

    sig do
      params(
        staff_user: T.nilable(::User),
        extra_trial_length: Integer
      ).returns(T::Boolean)
    end
    def extend_trial!(staff_user, extra_trial_length)
      GitHub.logger.with_named_tags(
        "gh.copilot.business_trial.id" => id,
        "gh.copilot.business_trial.previous_state" => state,
        "gh.copilot.business_trial.previous_started_at" => started_at,
        "gh.copilot.business_trial.previous_ends_at" => ends_at,
        "gh.org.id" => trialable.id
      ) do
        GitHub.logger.info(
          "Extending business trial",
          "gh.copilot.business_trial.state" => :extended,
          "gh.copilot.business_trial.extended_by" => staff_user&.display_login || "unknown"
        )

        new_trial_length = self.trial_length + extra_trial_length

        new_ends_at = if self.started?
          self.ends_at + extra_trial_length.days
        elsif self.ended?
          self.ends_at = Date.current + extra_trial_length.days
        else
          self.ends_at
        end

        result = update!(
          ends_at: new_ends_at,
          trial_length: new_trial_length,
          state: :extended,
        )

        staff_actor = staff_user || trialable.admins.first
        Copilot::Instrumenter.instrument_copilot_business_trial_extended(staff_actor, self, 0, new_trial_length)
        check_status!
        result
      end
    end

    sig do
      params(
        staff_user: T.nilable(::User),
        new_trial_length: Integer,
        new_copilot_plan: String
      ).returns(T::Boolean)
    end
    def convert_trial!(staff_user, new_trial_length: 30, new_copilot_plan: "enterprise")
      GitHub.logger.with_named_tags(
        "gh.copilot.business_trial.id" => id,
        "gh.copilot.business_trial.previous_copilot_plan" => copilot_plan,
        "gh.copilot.business_trial.previous_state" => state,
        "gh.copilot.business_trial.previous_started_at" => started_at,
        "gh.copilot.business_trial.previous_ends_at" => ends_at,
        "gh.org.id" => trialable.id
      ) do
        GitHub.logger.info(
          "Converting business trial",
          "gh.copilot.business_trial.new_state" => :pending,
          "gh.copilot.business_trial.new_copilot_plan" => new_copilot_plan,
          "gh.copilot.business_trial.converted_by" => staff_user&.display_login || "unknown"
        )

        previous_ends_at = self.ends_at
        old_copilot_plan = self.copilot_plan
        reason = "Trial converted to #{new_copilot_plan} plan"

        result = update!(
          copilot_plan: new_copilot_plan,
          ends_at: INACTIVE_DATE,
          started_at: INACTIVE_DATE,
          state: :pending,
          trial_length: new_trial_length,
        )

        # Set the CE policy to "No policy" if not enabled already upon Copilot Enterprise trial conversion
        copilot_org = Copilot::Organization.new(trialable)
        if !copilot_org.copilot_business&.copilot_for_dotcom_enabled?
          T.must(copilot_org.copilot_business).copilot_for_dotcom_no_policy!
        end

        # if the organization already seat assignments, we need to start the trial now
        if Copilot::SeatAssignment.for_organization(trialable).any?
          start_trial! if startable?
        end

        staff_actor = staff_user || trialable.admins.first
        Copilot::Instrumenter.instrument_copilot_business_trial_changed(
          staff_actor,
          self,
          reason,
          previous_ends_at,
          old_copilot_plan,
        )
        result
      end
    end

    sig { params(staff_user: T.nilable(::User)).returns(T::Boolean) }
    def upgrade!(staff_user)
      raise Copilot::Errors::OrgTrialUpgradeError, "Trial is not upgradable" unless upgradable? || can_force_upgrade?

      GitHub.logger.with_named_tags(
        "gh.copilot.business_trial.id" => id,
        "gh.copilot.business_trial.previous_state" => state,
        "gh.copilot.business_trial.previous_started_at" => started_at,
        "gh.copilot.business_trial.previous_ends_at" => ends_at,
        "gh.org.id" => trialable.id
      ) do
        start_date = started_at > DateTime.new(9998, 12, 31) ? Date.current : started_at
        GitHub.logger.info("Upgrading business trial", "gh.copilot.business_trial.state" => :upgraded)
        result = update!(started_at: start_date, ends_at: Date.current, state: :upgraded)

        # Delete existing free users and CfI subscriptions
        Copilot::BusinessTrials::UpgradeCleanupJob.perform_later(trialable.id) if copilot_plan_business?

        staff_actor = staff_user || trialable.admins.first
        Copilot::Instrumenter.instrument_copilot_business_trial_upgraded(staff_actor, self)
        result
      end
    end

    sig { returns T::Boolean }
    def restart!
      return false unless canceled?

      GitHub.logger.with_named_tags(
        "gh.copilot.business_trial.id" => id,
        "gh.copilot.business_trial.previous_state" => state,
        "gh.copilot.business_trial.previous_ends_at" => ends_at,
        "gh.org.id" => trialable.id
      ) do
        GitHub.logger.info("Restarting trial", "gh.copilot.business_trial.state" => :pending)
        start_date = started_at > DateTime.new(9998, 12, 31) ? Date.current : started_at
        result = update!(started_at: start_date, ends_at: Date.current + trial_length.days, state: :pending)

        result
      end
    end

    sig { returns(T::Boolean) }
    def cancel!
      GitHub.logger.with_named_tags(
        "gh.copilot.business_trial.id" => id,
        "gh.copilot.business_trial.previous_state" => state,
        "gh.copilot.business_trial.previous_ends_at" => ends_at,
        "gh.org.id" => trialable.id
      ) do
        GitHub.logger.info("Canceling trial", "gh.copilot.business_trial.state" => :canceled)
        start_date = started_at > DateTime.new(9998, 12, 31) ? Date.current : started_at
        result = update!(started_at: start_date, ends_at: Date.current, state: :canceled)

        organization_id = trialable_id

        # - Copilot Business trial: Delete all the seats and seat assignemnts
        # - Copilot Enterprise trial: Keep all the seats and seat assignemnts as the org is still under the Copilot Business plan
        if self.copilot_plan_business?
          Copilot::Seat.where(organization_id: organization_id).each do |seat|
            GitHub.logger.info("Removing seat", "gh.copilot.seat.id" => seat.id)
            seat.cancel!(reason: :trial_canceled)
          end

          Copilot::SeatAssignment.where(organization_id: organization_id).each do |seat_assignment|
            GitHub.logger.info("Removing seat assignment", "gh.copilot.seat_assignment.id" => seat_assignment.id)
            seat_assignment.destroy!
          end
        end

        result
      end
    end

    sig { returns(T::Boolean) }
    def active?
      ACTIVE_STATES.include?(state)
    end

    sig { returns(T::Boolean) }
    def ongoing?
      ONGOING_STATES.include?(state)
    end

    sig { params(expires_at: Date).void }
    def update_expiration!(expires_at)
      GitHub.logger.with_named_tags(
        "gh.copilot.business_trial.id" => id,
        "gh.copilot.business_trial.state" => state,
        "gh.copilot.business_trial.previous_ends_at" => ends_at,
        "gh.copilot.business_trial.ends_at" => expires_at,
        "gh.org.id" => trialable.id
      ) do
        if expires_at > Date.current
          GitHub.logger.info("Syncing trial to organization or business")
          update!(ends_at: expires_at)
          check_status!
        else
          GitHub.logger.info("Not syncing because expires_at is in past")
          cancel!
        end
      end
    end

    sig { void }
    def check_status!
      GitHub.logger.with_named_tags(
        "gh.copilot.business_trial.id" => id,
        "gh.copilot.business_trial.previous_state" => state,
        "gh.org.id" => trialable&.id
      ) do
        if ends_at <= Time.zone.now
          return if expired?
          GitHub.logger.info("Setting trial to expired")
          expired!
        elsif ends_at <= 1.day.from_now
          return if final_day?
          GitHub.logger.info("Setting trial to final_day")
          final_day!
        elsif ends_at <= 5.days.from_now
          return if nearly_over?
          GitHub.logger.info("Setting trial to nearly_over")
          nearly_over!
        elsif ends_at <= 15.days.from_now
          return if half_over?
          GitHub.logger.info("Setting trial to half_over")
          half_over!
        end
      end
    end

    # So, we made this table and set started_at to be NOT NULL
    # but we didn't set a default value.
    sig { returns(T::Boolean) }
    def started?
      return false unless active?
      started_at.to_date != INACTIVE_DATE
    end

    sig { returns(T::Boolean) }
    def ended?
      return false if active?
      ends_at.to_date < Date.current || canceled? || expired? || upgraded?
    end

    sig { returns(T::Boolean) }
    def has_trial?
      ends_at.to_date > Date.current
    end

    sig { returns(Integer) }
    def days_left
      (ends_at.to_date - Date.current).to_i.clamp(0, 999)
    end

    sig { returns(T.nilable(T::Boolean)) }
    def upgradable?
      return false unless in_upgradable_state?
      return false unless trialable_is_copilot_billable?

      return eligible_for_copilot_enterprise_features? if copilot_plan_enterprise?

      true
    end

    sig { returns(T::Boolean) }
    def cancelable?
      !canceled? && !expired? && !upgraded?
    end

    sig { params(skip_copilot_for_dotcom_enabled_check: T::Boolean).returns(T::Boolean) }
    def startable?(skip_copilot_for_dotcom_enabled_check: false)
      return false unless pending?
      return true if copilot_plan_business?

      # At this point, the trial would be copilot_plan_enterprise?
      return true if skip_copilot_for_dotcom_enabled_check

      Copilot::Organization.new(trialable).copilot_for_dotcom_enabled?
    end

    sig { returns(T::Boolean) }
    def can_be_converted_to_copilot_enterprise_trial?
      copilot_plan_business? && CONVERTIBLE_TO_CE_STATES.include?(state)
    end

    sig { returns(T::Boolean) }
    def trialable_business_already_on_copilot_enterprise?
      business = trialable.business

      return false if business.nil?

      copilot_business = Copilot::Business.new(business)
      copilot_business.copilot_plan_enterprise? || GitHub.flipper[:copilot_for_enterprise].enabled?(business)
    end

    sig { returns(T.nilable(T::Boolean)) }
    def trialable_is_copilot_billable?
      Copilot::Organization.new(trialable).copilot_billable?
    end

    sig { returns(T::Boolean) }
    def show_status_notification?
      pending? || active? || expired?
    end

    # In stafftools, we expose the ability to force a trial into an upgraded state.
    # We do this because sales will sometimes allow a trial to expire (instead of marking it as upgraded
    # or cancelled) after an enterprise has purchased Copilot.
    # This leads to an annoying issue for customers, where they can use Copilot, but they continue to see
    # banners saying their Copilot trial has expired.
    sig { returns(T::Boolean) }
    def can_force_upgrade?
      # If not expired, there is nothing to upgrade
      return false unless expired?

      business = trialable.business
      # This probably shouldn't happen, an org requires a parent business to have a trial in the first place
      return false if business.nil?

      copilot_biz = Copilot::Business.new(business)
      # Finally, if the business is billable and has existing seats, we can force the upgrade.
      copilot_biz.copilot_billable? && copilot_biz.copilot_enabled? && Copilot::Seat.for_business(copilot_biz.business_object).count.positive?
    end

    sig { returns(String) }
    def display_name
      "Copilot #{copilot_plan.capitalize} Trial"
    end

    sig { returns(String) }
    def short_display_name
      return "CE Trial" if copilot_plan_enterprise?

      "CB Trial"
    end

    sig { returns({ started: T::Boolean, ended: T::Boolean, has_trial: T::Boolean, upgradable: T.nilable(T::Boolean), cancelable: T::Boolean, days_left: Integer, trial_length: Integer, started_at: ActiveSupport::TimeWithZone, ends_at: ActiveSupport::TimeWithZone, active: T::Boolean, expired: T::Boolean, pending: T::Boolean, copilot_plan: String }) }
    def to_object
      {
        started: started?,
        ended: ended?,
        has_trial: has_trial?,
        upgradable: upgradable?,
        cancelable: cancelable?,
        days_left: days_left,
        started_at: started_at,
        ends_at: ends_at,
        trial_length: trial_length,
        active: active?,
        expired: expired?,
        pending: pending?,
        copilot_plan: copilot_plan,
      }
    end

    sig { returns(T.nilable(T::Boolean)) }
    def extendable?
      active?
    end

    sig { void }
    def process_disabling_copilot_enterprise_features
      # This method is used for when a Copilot Enterprise trial is canceled or expired.
      # During cancelation, this gets called by the copilot business trial controller and expiration job (twice just in case).
      GitHub.logger.with_named_tags(
        "gh.copilot.business_trial.id" => id,
        "gh.org.id" => trialable.id
      ) do
        business = trialable.business

        # There is a possibility of an organization being removed from their enterprise while on Copilot Enterprise trial.
        # In that case, we should be disabling the organization's Copilot enterprise policy only.
        if business.nil?
          GitHub.logger.info("Disabling Copilot Enterprise features for the organization", "gh.org.id" => trialable.id)
          Copilot::Organization.new(trialable).copilot_for_dotcom_disabled!
        else
          copilot_business = Copilot::Business.new(business)

          # Do nothing if the enterprise is already on a Copilot Enterprise plan and the Copilot enterprise policy is enabled for all the orgs
          if copilot_business.copilot_plan_enterprise? && copilot_business.copilot_for_dotcom_enabled?
            GitHub.logger.info("Leaving Copilot Enterprise features for the business and organization as enabled as the business's copilot plan is already enterprise", "gh.business.id" => business.id)
            return
          end

          # Do nothing if the enterprise is on the waitlist and the Copilot enterprise policy is enabled for all the orgs
          # This scenario should not happen because a trial cannot be created if they are on the waitlist but just in case
          if GitHub.flipper[:copilot_for_enterprise].enabled?(business) && copilot_business.copilot_for_dotcom_enabled?
            GitHub.logger.info("Leaving Copilot Enterprise features for the business and organization as enabled as the business is on the waitlist feature flag", "gh.business.id" => business.id)
            return
          end

          if should_disable_copilot_enterprise_features_for_org_only?
            GitHub.logger.info("Disabling Copilot Enterprise features for the organization", "gh.org.id" => trialable.id)
            Copilot::Organization.new(trialable).copilot_for_dotcom_disabled!(false) unless Copilot::Organization.new(trialable).copilot_for_dotcom_disabled?
          else
            # Copilot Enterprise trials are offered at the org level so we don't want to send an email to all the Copilot users across the organizations
            GitHub.logger.info("Disabling Copilot Enterprise features for the business", "gh.business.id" => business.id)
            copilot_business.copilot_for_dotcom_disabled!(send_email: false)
          end
        end
      end
    end

    sig { returns(T.any(T.class_of(CopilotEnterpriseMailer), T.class_of(CopilotForBusinessMailer))) }
    def mailer_class
      return CopilotEnterpriseMailer if copilot_plan_enterprise?

      CopilotForBusinessMailer
    end

    private

    sig { returns(T.nilable(T::Boolean)) }
    def in_upgradable_state?
      !canceled? && !expired? && !upgraded?
    end

    sig { returns(T.nilable(T::Boolean)) }
    def eligible_for_copilot_enterprise_features?
      return false if trialable.is_a?(::Organization) && trialable.business.nil?

      Copilot::Seat.for_organization(trialable).count > 0
    end

    sig { void }
    def ends_at_must_be_after_started_at
      return if ends_at.blank? || started_at.blank?

      errors.add(:ends_at, "must be after the start date") if ends_at < started_at
    end

    sig { void }
    def trialable_must_be_organization
      return if trialable.blank?

      errors.add(:trialable, "must be an Organization") unless trialable.is_a?(::Organization)
    end

    sig { void }
    def trialable_must_be_unique
      return if trialable.blank?

      existing_trial = Copilot::BusinessTrial.find_by(trialable_type: trialable.class.to_s, trialable_id: trialable.id)

      # This check is necessary when updating an existing record,
      # as we don't want the record to consider itself as a duplicate.
      if existing_trial && existing_trial != self
        errors.add(:trialable, "has already been taken")
      end
    end

    sig { void }
    def trialable_must_not_be_standalone_org
      return if trialable.blank?
      return unless trialable.is_a?(::Organization)

      errors.add(:trialable, "must not be a standalone Organization") if trialable.business.nil?
    end

    sig { void }
    def trialable_must_be_eligible_for_copilot_enterprise
      # We aren't allowing the creation of Copilot Enterprise trials if:
      # - Their business is already on the Copilot Enterprise SKU for real; OR
      # - Their business is part of the Copilot Enterprise Beta waitlist
      errors.add(:trialable, "business is already on Copilot Enterprise") if trialable_business_already_on_copilot_enterprise?
    end

    sig { void }
    def trialable_must_be_billable
      errors.add(:trialable, "must be Copilot billable") unless trialable_is_copilot_billable?
    end

    sig { void }
    def notify_admin_of_trial_creation
      mailer_class.trial_welcome(trialable, trial_length).deliver_later
    end

    sig { void }
    def notify_users_of_trial_expiration
      return if copilot_plan_business?
      return if trialable_business_already_on_copilot_enterprise?

      Copilot::Seat.for_organization(trialable).each do |seat|
        CopilotEnterpriseMailer.trial_expired_for_user(trialable, seat.assigned_user).deliver_later
      end
    end

    sig { void }
    def on_state_change
      return unless saved_change_to_state?
      case
      when half_over?
        mailer_class.trial_half_over(trialable).deliver_later
      when nearly_over?
        mailer_class.trial_nearly_over(trialable).deliver_later
      when final_day?
        mailer_class.trial_final_day(trialable).deliver_later
      when expired?
        Copilot::BusinessTrials::ExpirationJob.perform_later(trialable.id)
        mailer_class.trial_expired(trialable).deliver_later
        notify_users_of_trial_expiration
      when canceled?
        Copilot::BusinessTrials::ExpirationJob.perform_later(trialable.id)
      end
    end

    # Disable the Copilot Enterprise features at the enterprise level only if
    # - the enterprise's copilot plan is NOT Copilot Enterprise OR
    # - the enterprise is NOT on the waitlist OR
    # - there are NO other orgs on a Copilot Enterprise trial
    # - the enterprise does not have any orgs on Copilot Enterprise plan under mixed licenses
    sig { returns(T.nilable(T::Boolean)) }
    def should_disable_copilot_enterprise_features_for_org_only?
      business = trialable.business
      copilot_business = Copilot::Business.new(business)

      return true if copilot_business.copilot_plan_enterprise?
      return true if business.feature_enabled?(:copilot_for_enterprise)

      other_ongoing_org_trials = Copilot::BusinessTrial.ongoing
        .for_organization_ids(business.organization_ids - [trialable.id])
        .where(copilot_plan: "enterprise")
      return true if other_ongoing_org_trials.any?

      business.feature_enabled?(:copilot_mixed_licenses) && copilot_business.number_of_enterprise_organizations > 0
    end
  end
end
