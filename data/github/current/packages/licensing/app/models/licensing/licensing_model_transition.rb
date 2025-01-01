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

    validates_inclusion_of :ghas_only, in: [true, false]
    validates_inclusion_of :unbundle_ghas, in: [true, false]
    validates_presence_of :customer
    validates_presence_of :transition_date
    validates_inclusion_of :status, in: statuses.keys
    validates_inclusion_of :licensing_model, in: licensing_models.keys
    validates :transition_date, comparison: { greater_than_or_equal_to: Date.today }, if: :transition_date_changed?
    validate :must_transition_to_different_model, if: proc { |a| %w[scheduled].include?(a.status) }
    validate :ghas_volume_transition
    validates_uniqueness_of :status,
      scope: :customer_id,
      conditions: -> { where(status: "scheduled") },
      message: ": There is already a scheduled transition for this customer."

    scope :for_today, -> { where(transition_date: ..Date.current) }

    after_create_commit :instrument_creation

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

        if unbundle_ghas
          # Unbundle security configurations and settings when SKU unbundling transitions are supported
          TransitionUnbundleGhasForBusinessJob.perform_later(
            business,
            actor: T.must(actor),
            code_security_enablement_strategy: code_security_enablement_strategy.to_sym,
            skip_billing_config_changes: false,
          )
        else
          business.mark_advanced_security_as_metered_for_entity(actor: T.must(actor))
          business.set_advanced_security_seats_for_entity(seats: 0, actor: T.must(actor), is_stafftools_action: true)
        end
      elsif licensing_model == "volume"
        # Unlike with the transition to metered, which restricts which GHAS offerings are available,
        # TransitionEnterpriseToVolumeLicensingJob does not make any changes to the GHAS model
        # so there is no need to unbundle/rebundle here.
        TransitionEnterpriseToVolumeLicensingJob.perform_later(
          business,
          licensing_model_transition_id: id,
          coupon_code: coupon_code,
          ghas_only: ghas_only,
        )
      end

      update!(status: "queued")
    end

    sig { void }
    def cancel!
      update!(status: "cancelled")
    end

    sig { void }
    def date
      transition_date.strftime("%B %e, %Y")
    end

    private

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

    sig { returns(Business) }
    def business
      T.must(customer&.business)
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
