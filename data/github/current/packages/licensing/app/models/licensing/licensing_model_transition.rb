# typed: strict
# frozen_string_literal: true

module Licensing
  class LicensingModelTransition < ApplicationRecord::Domain::Billing
    include GitHub::Validations
    include Instrumentation::Model

    belongs_to :customer, class_name: "::Customer", required: true
    belongs_to :actor, class_name: "::User", required: true

    STATUSES = T.let([%w[Scheduled scheduled], %w[Queued queued], %w[Running running], %w[Success success], %w[Failed failed], %w[Cancelled cancelled]], T::Array[T::Array[String]])
    LICENSING_MODELS = T.let([%w[Volume volume], %w[Metered metered]], T::Array[T::Array[String]])

    enum :status, { scheduled: 0, queued: 1, running: 2, success: 3, failed: 4, cancelled: 5 }
    enum :licensing_model, { volume: 0, metered: 1 }
    enum :code_security_enablement_strategy, { do_not_enable_code_security: 0, enable_code_security: 1, right_size: 2 }

    # unbundle_ghas used to be treated as a boolean, even though it is a tinyint(1) in the database.
    # It is now an enum to allow for not making any changes to the GHAS offering during the transition.
    # The old boolean values are still supported for backwards compatibility
    attribute :unbundle_ghas, :integer
    enum :unbundle_ghas, { bundle_ghas: 0, unbundle_ghas: 1, noop_ghas: 2 }, default: :noop_ghas

    validates_inclusion_of :ghas_only, in: [true, false]

    validates_presence_of :customer
    validates_presence_of :transition_date
    validates_inclusion_of :status, in: statuses.keys
    validates_inclusion_of :licensing_model, in: licensing_models.keys
    validates :transition_date, comparison: { greater_than_or_equal_to: Date.current }, if: :transition_date_changed?
    validate :must_transition_to_different_model, if: proc { |t| %w[scheduled].include?(t.status) }
    validate :ghas_volume_transition
    validates_uniqueness_of :status,
      scope: :customer_id,
      conditions: -> { where(status: "scheduled") },
      message: ": There is already a scheduled transition for this customer."

    scope :for_today, -> { where(transition_date: ..Date.current) }
    scope :for_tomorrow, -> { where(transition_date: Date.current + 1.day) }

    after_create_commit :send_schedule_notification
    after_create_commit :instrument_creation
    after_save_commit :send_cancel_notification
    after_save_commit :send_complete_notification

    sig { void }
    def enqueue
      # This should almost never happen in the real world, but we want to add it as a safeguard.
      unless customer
        update!(status: "failed", message: "Customer does not exist or is not valid")
        return
      end

      if licensing_model == "metered"
        TransitionEnterpriseToMeteredLicensingJob.perform_later(
          business,
          actor: T.must(actor),
          licensing_model_transition_id: id,
          unbundle_ghas: false # soon to be deprecated, but kept for backwards compatibility
        )

        if business.has_active_advanced_security_subscription?
          business.cancel_advanced_security_subscription(
            actor: T.must(actor),
            force: true,
          )
        end

        if unbundle_ghas?
          # Unbundle security configurations and settings when SKU unbundling transitions are supported
          TransitionUnbundleGhasForBusinessJob.perform_later(
            business,
            actor: T.must(actor),
            code_security_enablement_strategy: code_security_enablement_strategy.to_sym,
            skip_billing_config_changes: false,
          )
        elsif bundle_ghas?
          business.mark_advanced_security_as_metered_for_entity(actor: T.must(actor))
          business.set_advanced_security_seats_for_entity(seats: 0, actor: T.must(actor), is_stafftools_action: true)
        end
      elsif licensing_model == "volume"
        # Unlike with the transition to metered, which restricts which GHAS offerings are available,
        # TransitionEnterpriseToVolumeLicensingJob does not make any changes to the GHAS model
        # so there is no need to unbundle/rebundle here.
        TransitionEnterpriseToVolumeLicensingJob.perform_later(business, licensing_model_transition_id: id)
      end

      queued!
    end

    sig { params(coupon_code: T.nilable(String)).returns(T::Boolean) }
    def apply_coupon_code(coupon_code)
      return false if coupon_code.blank?

      if metered?
        errors.add(:coupon_code, "Coupons can only be applied when transitioning to volume licensing.")
        return false
      end

      unless business.validate_coupon(coupon_code)
        errors.add(:coupon_code, "Coupon code validation failed.")
        return false
      end

      self.coupon_code = coupon_code

      true
    end

    sig { returns(T::Boolean) }
    def scheduled_for_future_date?
      transition_date > Date.current
    end

    sig { returns(T::Boolean) }
    def scheduled_for_today?
      transition_date == Date.current
    end

    sig { returns(T::Boolean) }
    def scheduled_for_tomorrow?
      transition_date == Date.current + 1.day
    end

    sig { void }
    def send_day_before_notice_notification
      return unless FeatureFlag.vexi.enabled?(:licensing_metered_transition_emails, business, default: false)
      return unless scheduled_for_tomorrow?
      return unless metered?

      MeteredTransitionMailer.day_before_notice(self).deliver_later
    end

    sig { void }
    def date
      transition_date.strftime("%B %e, %Y")
    end

    sig { returns(Business) }
    def business
      T.must(customer&.business)
    end

    sig { returns(T::Hash[T.any(String, Symbol), Integer]) }
    def self.ghas_options
      # Sad. Rails is pluralizing "ghas" to "ghave", because of "has" suffix.
      unbundle_ghave
    end

    private

    sig { void }
    def send_schedule_notification
      return unless FeatureFlag.vexi.enabled?(:licensing_metered_transition_emails, business, default: false)
      return unless scheduled_for_future_date?
      return unless metered?

      MeteredTransitionMailer.schedule(self).deliver_later
    end

    sig { void }
    def send_cancel_notification
      return unless FeatureFlag.vexi.enabled?(:licensing_metered_transition_emails, business, default: false)
      return unless saved_change_to_status?
      return unless cancelled?
      return unless metered?

      MeteredTransitionMailer.cancel(business).deliver_later
    end

    sig { void }
    def send_complete_notification
      return unless FeatureFlag.vexi.enabled?(:licensing_metered_transition_emails, business, default: false)
      return unless saved_change_to_status?
      return unless success?
      return unless metered?

      MeteredTransitionMailer.complete(business).deliver_later
    end

    sig { void }
    def must_transition_to_different_model
      return unless customer

      if ghas_only
        current_model = business.advanced_security_metered_for_entity? ? "metered" : "volume"
      else
        current_model = T.must(customer).metered_plan? ? "metered" : "volume"
      end

      return if current_model != licensing_model
      errors.add(:licensing_model, "The customer is already on the selected licensing model.")
    end

    sig { void }
    def ghas_volume_transition
      return unless customer
      return true unless ghas_only

      if licensing_model == "volume" && T.must(customer).metered_plan?
        errors.add(:ghas_only, "Business must be volume GHE before transitioning GHAS to volume.")
      end

      true
    end

    sig { void }
    def instrument_creation
      instrument :create
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def event_payload
      {
        customer: customer,
        business: business,
        business_id: business.id,
        licensing_model_transition_id: id,
        licensing_model: licensing_model,
        status: status,
        ghas_only: ghas_only,
        unbundle_ghas: unbundle_ghas
      }
    end

    sig { returns(Symbol) }
    def event_prefix
      :licensing_model_transition
    end
  end
end
