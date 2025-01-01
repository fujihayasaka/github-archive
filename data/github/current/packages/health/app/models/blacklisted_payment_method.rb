# rubocop:disable Naming/InclusiveLanguage TODO: Rename to BlocklistedPaymentMethod
# typed: strict
# frozen_string_literal: true

# Represents a `flagged` payment method that could be related
# to spam-like/unacceptable behavior. This data be all like:
#
# * user_id                  - Last associated user
# * unique_number_identifier - Braintree's unique id for credit cards.
# * paypal_email             - Their paypal email on file.
#
class BlacklistedPaymentMethod < ApplicationRecord::Domain::Users
  extend T::Sig
  include GitHub::Validations
  # Public:
  belongs_to :user
  validates_presence_of :user
  validate :presence_of_identifier
  validates :paypal_email, unicode3: true

  class Consequence < T::Enum
    enums do
      Suspended = new("suspended")
      BillingLocked = new("billing_locked")
    end
  end

  attribute :reason, :string
  attribute :consequence, :string
  enum :consequence, { suspended: Consequence::Suspended.serialize, billing_locked: Consequence::BillingLocked.serialize }

  # @param card_fingerprint [String] The card fingerprint to lookup. Can be a Stripe token or a PayPal email.
  # @returns [PaymentMethod] The payment method that matches the card fingerprint.
  sig { params(card_fingerprint: String).returns(T.nilable(BlacklistedPaymentMethod)) }
  def self.find_by_card_fingerprint(card_fingerprint) # rubocop:disable GitHub/FindByDef
    find_by("unique_number_identifier = :card_fingerprint OR paypal_email = :card_fingerprint", card_fingerprint: card_fingerprint)
  end

  # Gets all records for a given card fingerprint
  sig { params(card_fingerprint: String).returns(ActiveRecord::Relation) }
  def self.find_all_by_card_fingerprint(card_fingerprint)
    where("unique_number_identifier = :card_fingerprint or paypal_email = :card_fingerprint", card_fingerprint: card_fingerprint)
  end

  sig { params(user: Billing::Types::Account, payment_method: PaymentMethod, reason: T.nilable(String), consequence: T.nilable(Consequence), force: T::Boolean, actor: User).returns(T::Array[BlacklistedPaymentMethod]) }
  def self.create_for_all_users(user, payment_method, reason: nil, consequence: nil, force: false, actor: User.ghost)
    card_fingerprint = payment_method.card_fingerprint
    return [] unless card_fingerprint.present?

    payment_method_records = PaymentMethod.with_card_fingerprint(card_fingerprint).joins("LEFT OUTER JOIN blacklisted_payment_methods ON blacklisted_payment_methods.unique_number_identifier = payment_methods.unique_number_identifier OR blacklisted_payment_methods.paypal_email = payment_methods.paypal_email")
      .where("blacklisted_payment_methods.user_id != payment_methods.user_id OR blacklisted_payment_methods.user_id IS NULL")
      .includes(:user)
    users_to_blocklist = payment_method_records.map(&:user)
    if users_to_blocklist.empty?
      # If there's no user to blocklist, return the entry associated to the user
      return find_all_by_card_fingerprint(card_fingerprint).where(user_id: user.id).to_a
    end
    users_to_blocklist.map do |user|
      create_from_user_and_payment_method(user, payment_method, reason:, consequence:, force:, actor:)
    end
  end

  # Public: Generate a Blacklisted PaymentMethod from a User and a Payment Method.
  #
  # user - A User with a PaymentMethod
  # payment_method - A PaymentMethod
  # reason - A written reason that the payment method is being blocklisted
  # consequence - A consequence of the blocklisting
  # force - When false, the consequence will default to the same reason and consequence of the latest BlacklistedPaymentMethod if it exists. Set it to true to set a new reason and /or consequence.
  #
  # returns a BlacklistedPaymentMethod
  sig { params(user: Billing::Types::Account, payment_method: PaymentMethod, reason: T.nilable(String), consequence: T.nilable(Consequence), force: T::Boolean, actor: User).returns(BlacklistedPaymentMethod) }
  def self.create_from_user_and_payment_method(user, payment_method, reason: nil, consequence: nil, force: false, actor: User.ghost)
    payload = {}
    begin
      blocklisted_payment_method = find_by_payment_method(payment_method)
      consequence = consequence&.serialize
      if blocklisted_payment_method.present?
        consequence = force ? consequence : blocklisted_payment_method.consequence
        reason = force ? reason : blocklisted_payment_method.reason
      end
      create \
        user_id: user.try(:id),
        unique_number_identifier: payment_method.try(:unique_number_identifier),
        paypal_email: payment_method.try(:paypal_email),
        reason: reason,
        consequence: consequence || Consequence::Suspended.serialize
    rescue ActiveRecord::RecordNotUnique
      payload.update(error: "Payment method has already been blocklisted")
      T.must(blocklisted_payment_method)
    ensure
      payload.update(actor: actor, consequence: consequence, reason: reason)
      payload.update(account_payload(account: user))
      GitHub.instrument("blocklisted_payment_method.add", payload)
    end
  end

  # Gets the latest BlacklistedPaymentMethod for a given PaymentMethod
  sig { params(payment_method: PaymentMethod).returns(T.nilable(BlacklistedPaymentMethod)) }
  def self.find_by_payment_method(payment_method)  # rubocop:disable GitHub/FindByDef
    card_fingerprint = payment_method.card_fingerprint
    return nil unless card_fingerprint
    find_all_by_card_fingerprint(card_fingerprint).order(created_at: :desc).first
  end


  # Removes a payment method from the blocklist
  sig { params(card_fingerprint: String, actor: User, reason: String, undo_consequence: T.nilable(T::Boolean)).returns(T::Boolean) }
  def self.remove_payment_method(card_fingerprint:, actor:, reason:, undo_consequence: false)
    blocklisted_payment_methods = find_all_by_card_fingerprint(card_fingerprint)
    return true if blocklisted_payment_methods.empty?

    all_removed = BlacklistedPaymentMethod.destroy(blocklisted_payment_methods.map(&:id))
    all_removed && blocklisted_payment_methods.each do |blocklisted_payment_method|
      payload = { actor: actor, reason_was: blocklisted_payment_method.reason, consequence_was: blocklisted_payment_method.consequence, removal_reason: reason, undo_suspension_or_billing_locked: undo_consequence }
      payment_method_owner = blocklisted_payment_method.user
      payload.update(account_payload(account: payment_method_owner)) if payment_method_owner
      if payment_method_owner && undo_consequence
        if blocklisted_payment_method.consequence_is_billing_locked?
          payment_method_owner.customer&.remove_disabled_reason(Billing::Public::BillingDisabledReasons::BlocklistedPaymentMethod)
          payment_method_owner.enable_or_disable!
        elsif blocklisted_payment_method.consequence_is_suspended?
          payment_method_owner.suspended? && payment_method_owner.unsuspend(reason, actor: actor)
        end
      end
      GitHub.instrument("blocklisted_payment_method.remove", payload)
    end

    !!all_removed
  end

  sig { params(account: Billing::Types::Account).returns(T::Hash[String, String]) }
  private_class_method def self.account_payload(account:)
    if account.is_a?(Business)
      { business: account }
    elsif account.is_a?(Organization)
      { org: account }
    else
      { user: account }
    end
  end

  # Public: Returns the non-null unique identifier
  #
  # Returns a String
  sig { returns(String) }
  def payment_identifier
    T.must(unique_number_identifier || paypal_email)
  end

  # Public: Returns all users using this blacklist payment method
  sig { returns(T::Array[T.nilable(Billing::Types::Account)]) }
  def users
    return [] if unique_number_identifier.blank? && paypal_email.blank?

    records = if unique_number_identifier.present?
      PaymentMethod.where("unique_number_identifier = ?", unique_number_identifier).includes(:user)
    else
      PaymentMethod.where("paypal_email = ?", paypal_email).includes(:user)
    end
    records.map(&:user)
  end

  # Public: Performs the consequence on the user(s) associated to the payment method
  sig { params(instrument_abuse_classification: T::Boolean, include_all_users: T::Boolean).void }
  def execute_consequence(instrument_abuse_classification: true, include_all_users: false)
    return unless user.present?
    targets = include_all_users ? users : [user]

    targets.each do |target|
      next if target.nil?

      if consequence_is_billing_locked?
        target.disable!(reason: Billing::Public::BillingDisabledReasons::BlocklistedPaymentMethod)
      elsif consequence_is_suspended?
        target.suspend(
          "Using blacklisted payment method",
          instrument_abuse_classification: instrument_abuse_classification,
        )
      else
        Failbot.report!(
          StandardError.new("Unexpected consequence for blocklisted payment method"),
          { "gh.target.id" => target.id, "gh.blocklisted_payment.id" => self.id }
        )
      end
    end
  end

  sig { returns(T::Boolean) }
  def consequence_is_billing_locked?
    billing_locked?
  end

  sig { returns(T::Boolean) }
  def consequence_is_suspended?
    suspended?
  end

  private

  # Private: Checks to ensure we have either identifier field for the
  # Blacklisted PaymentMethod.
  #
  sig { void }
  def presence_of_identifier
    unless unique_number_identifier.present? || paypal_email.present?
      errors.add(:base, "Must have either unique_number_identifier or paypal_email")
    end
  end
end

# rubocop:enable Naming/InclusiveLanguage
