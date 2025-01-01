# typed: strict
# frozen_string_literal: true

module Licensing
  class GhasUnbundleTransition < ApplicationRecord::Domain::Billing
    include GitHub::Validations
    include Instrumentation::Model

    belongs_to :customer, class_name: "::Customer", required: true
    belongs_to :actor, class_name: "::User", required: true

    STATUSES = T.let([%w[Scheduled scheduled], %w[Queued queued], %w[Running running], %w[Success success], %w[Failed failed], %w[Cancelled cancelled]], T::Array[T::Array[String]])
    TARGET_SKU_STATE = T.let([%w[Unbundled unbundled], %w[Bundled bundled]], T::Array[T::Array[String]])

    enum :status, { scheduled: 0, queued: 1, running: 2, success: 3, failed: 4, cancelled: 5 }
    enum :target_sku_state, { unbundled: 0, bundled: 1 }

    validates_presence_of :customer
    validates_presence_of :transition_date
    validates_inclusion_of :status, in: statuses.keys
    validates_inclusion_of :target_sku_state, in: target_sku_states.keys
    validates :transition_date, comparison: { greater_than_or_equal_to: Date.today }, if: :transition_date_changed?
    validate :must_transition_to_different_sku_state
    validates_uniqueness_of :status,
      scope: :customer_id,
      conditions: -> { where(status: "scheduled") },
      message: ": There is already a scheduled transition for this customer."

    scope :for_today, -> { where(transition_date: ..Date.current) }

    after_create_commit :instrument_creation

    sig { params(perform_now: T::Boolean).void }
    def enqueue(perform_now: false)
      # The target SKU state is "unbundled" by default, so we only need to check explicitly when it is
      # set to "bundled" for the rollback scenario
      if target_sku_state == "bundled"
        Licensing::TransitionRebundleGhasForBusinessJob.perform_later(business, actor: T.must(actor), transition_id: id) unless perform_now
        Licensing::TransitionRebundleGhasForBusinessJob.perform_now(business, actor: T.must(actor), transition_id: id) if perform_now
      else
        Licensing::TransitionUnbundleGhasForBusinessJob.perform_later(business, actor: T.must(actor), transition_id: id) unless perform_now
        Licensing::TransitionUnbundleGhasForBusinessJob.perform_now(business, actor: T.must(actor), transition_id: id) if perform_now
      end

      update!(status: "queued") unless perform_now
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
    def must_transition_to_different_sku_state
      # this validation is not needed for enterprise since the transition only happens once on boot
      # and the license dictates the incoming SKU state
      return if GitHub.enterprise?
      return unless customer

      currently_bundled = business.advanced_security_products_bundled?
      return if currently_bundled && target_sku_state != "bundled"
      return if !currently_bundled && target_sku_state == "bundled"

      errors.add(:target_sku_state, "The customer is already on the target SKU state.")
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
        sku_unbundling_transition_id: id,
        target_sku_state: target_sku_state,
        status: status,
      }
    end

    sig { returns(Symbol) }
    def event_prefix
      :ghas_unbundle_transition
    end
  end
end
