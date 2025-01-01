# typed: strict
# frozen_string_literal: true

# Writes key events to audit log and reports stats for actions on a
# PaymentMethod.
#
# Audit Log Events:
#
# payment_method.create
# payment_method.update
# payment_method.remove
#
# Payload Hash:
#   :note                          - String human friendly note about the event.
#   :actor                         - User that took the action.
#   :user                          - User that owns this payment method OR
#   :org                           - Organization that owns this payment method.
#   :payment_processor_customer_id - Customer ID in the payment processor.
#   :payment_processor_type        - String "braintree", "zuora".
#   :payment_method                - String "paypal", "card", or "none".
#
#
# Datadog Keys:
#
# "billing.create"
# "billing.update"
# "billing.remove"
module PaymentMethod::InstrumentationDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PaymentMethod }

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    hash = {
      payment_processor_customer_id: payment_processor_customer_id,
      payment_processor_type: payment_processor_type,
      payment_method: payment_instrument,
      payment_method_id: id,
    }

    if business = customer&.business
      hash[:business] = business.slug
      hash[:business_id] = business.id
    elsif user&.organization?
      hash[:org] = user
    elsif user&.billable?
      hash[:user] = user
    end

    hash
  end

  # Public: Instrument the first time creation of a payment method.
  sig { params(actor: T.nilable(User)).void }
  def instrument_create(actor = nil)
    actor ||= cached_payment_method_change_actor

    actor_context = if actor&.site_admin?
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      { actor: actor }
    end
    instrument :create, actor_context.merge(note: event_note("Created"))

    GitHub.dogstats.increment("billing.create", tags: [
      "payment_processor:#{payment_processor_type}",
      "payment_instrument:#{payment_instrument}",
      "success:true",
    ])
  end

  # Public: Instrument the update of a payment method.
  sig { params(actor: T.nilable(User)).void }
  def instrument_update(actor = nil)
    return unless valid_payment_token?

    actor ||= cached_payment_method_change_actor
    actor_context = if actor&.site_admin?
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      { actor: actor }
    end
    instrument :update, actor_context.merge(note: event_note("Updated"))

    GitHub.dogstats.increment("billing.update", tags: [
      "payment_processor:#{payment_processor_type}",
      "payment_instrument:#{payment_instrument}",
      "success:true",
    ])
  end

  # Public: Instrument the failure to update a payment method.
  sig { params(actor: T.nilable(User), error_msg: String).void }
  def instrument_update_failure(actor, error_msg)
    actor_context = if actor&.site_admin?
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      { actor: actor }
    end
    instrument :update, actor_context.merge(note: "Error Updating: #{error_msg}")

    GitHub.dogstats.increment("billing.update", tags: [
      "payment_processor:#{payment_processor_type}",
      "payment_instrument:#{payment_instrument}",
      "success:false",
    ])
  end

  # Public: Instrument removal of payment details.
  sig { params(actor: T.nilable(User)).void }
  def instrument_clear(actor = nil)
    actor_context = if actor&.site_admin?
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      { actor: actor }
    end
    instrument :remove, actor_context.merge(note: "Removed payment details")
    GitHub.dogstats.increment("billing.remove",
      tags: ["payment_processor:#{payment_processor_type}",
      "success:true",
    ])
  end

  sig { returns(T.nilable(User)) }
  def cached_payment_method_change_actor
    actor_id = Billing::Kv.store.get(payment_method_change_key).value!
    return if actor_id.blank?
    User.find_by(id: actor_id)
  end

  sig { params(actor: T.nilable(User)).void }
  def cache_payment_method_change_actor(actor)
    return unless actor.present? && valid_payment_token?
    Billing::Kv.store.set(payment_method_change_key, actor.id.to_s, expires: 30.seconds.from_now)
  end

  private

  sig { returns(String) }
  def payment_instrument
    if credit_card?
      "card"
    elsif paypal?
      "paypal"
    else
      "none"
    end
  end

  sig { params(prefix: String).returns(String) }
  def event_note(prefix)
    if valid_payment_token? && credit_card?
      "#{prefix} credit card"
    elsif valid_payment_token? && paypal?
      "#{prefix} PayPal account"
    elsif valid_payment_token?
      "Valid payment token, unknown payment method"
    else
      "Cleared payment details"
    end
  end

  sig { returns(String) }
  def payment_method_change_key
    "payment_method_change:#{self.payment_token}"
  end
end
