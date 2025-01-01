# typed: strict
# frozen_string_literal: true

module Business::TradeScreeningDependency
  include TradeControls::AbstractTradeScreeningDependency
  include GitHub::Memoizer

  extend T::Helpers

  requires_ancestor { Business }

  extend ActiveSupport::Concern

  included do
    # similar to :profile but this is primarily populated and used
    # when the user is about to make a financial transaction
    T.bind(self, T.class_of(Business))
    self.has_one :trade_screening_record, dependent: :destroy, class_name: "AccountScreeningProfile", autosave: false, as: :owner,
      inverse_of: :owner
  end

  # Public: check if business has a valid personal profile for financial transactions with any of the address fields entered
  sig { override.returns(T::Boolean) }
  def has_saved_trade_screening_record_with_information?
    has_saved_trade_screening_record?(skip_validation_errors: true) && (
      trade_screening_record.address1.present? ||
      trade_screening_record.address2.present? ||
      trade_screening_record.city.present? ||
      trade_screening_record.region.present? ||
      trade_screening_record.postal_code.present? ||
      trade_screening_record.vat_code.present?
    )
  end

  sig { override.returns(T::Boolean) }
  def is_allowed_to_remove_billing_information?
    return false if self.invoiced?
    return false unless self.trial?
    return false unless self.self_serve_payment?

    super
  end

  sig { override.returns(T::Boolean) }
  def has_sdn_auto_sponsorable_restrictions?
    true # businesses can't be part of sponsor maintainer program
  end

  # Public: Used to check if an actor is allowed to have commercial interactions.
  # This check excludes `retry` screening status, and therefore, returns false
  # in such case.
  sig { override.params(feature_type: Symbol).returns(T::Boolean) }
  def has_commercial_interaction_restriction?(feature_type: :default)
    owner_has_sdn_restriction? feature_type: feature_type
  end

  # Public: used to check if the owner of the trade screening record is on
  # business terms of service
  sig { override.returns(T::Boolean) }
  def org_is_on_business_tos?
    return T.must(@org_is_on_business_tos) if defined?(@org_is_on_business_tos)

    tos = self.terms_of_service_type
    @org_is_on_business_tos = T.let(nil, T.nilable(T::Boolean))
    @org_is_on_business_tos = Organization::TermsOfService::BUSINESS_TERMS_OF_SERVICE_TYPES.include?(tos)
  end

  # Public: Returns object type for instrumentation logging
  sig { override.returns(Symbol) }
  def instrumentation_object_type
    :BUSINESS
  end

  sig { override.params(feature_type: Symbol).returns(T::Boolean) }
  def show_trade_screening_flash_notice?(feature_type: :default)
    feature_type != :direct_org_to_enterprise_upgrade
  end

  # Public: Suspend the user in compliance with SDN (specially designated nationals) protocols.
  # This type of suspension performs the following:
  #   * Suspends the user
  #   * Locks private repositories
  #   * Archives public repositories
  #   * Places a legal hold on the account
  #
  # staff_user: The staffer who is suspending the actor.
  # reason: reason for the suspension
  sig { override.params(staff_user: User, reason: String).returns(T::Boolean) }
  def sdn_suspend(staff_user:, reason:)
    raise AccountScreeningProfile::AccountScreeningProfileUpdateError, "Staff user is required!" if staff_user.blank?
    raise AccountScreeningProfile::AccountScreeningProfileUpdateError, "Reason is required!" if reason.blank?

    self.toggle_sdn_suspension_status(staff_user: staff_user, should_suspend: true, reason: reason)

    return false unless self.trade_screening_record.true_match?

    self.suspend(reason, actor: staff_user, hard_flag: true, sdn_suspension: true)

    # Add a staff note to the business for visibility
    self.add_sdn_suspension_staff_note(note: reason)
    true
  end

  # Public: SDN unsuspends an actor. This action is called through stafftools.
  #
  # staff_user: The staffer who is unsuspending the actor.
  # reason: reason for the unsuspension
  sig { override.params(staff_user: User, reason: String).returns(T::Boolean) }
  def sdn_unsuspend(staff_user:, reason:)
    raise AccountScreeningProfile::AccountScreeningProfileUpdateError, "Staff user is required!" if staff_user.blank?
    raise AccountScreeningProfile::AccountScreeningProfileUpdateError, "Reason is required!" if reason.blank?

    self.toggle_sdn_suspension_status(staff_user: staff_user, should_suspend: false, reason: reason)

    self.unsuspend(reason, actor: staff_user, sdn_suspension: true)

    # Add a staff note to the business for visibility
    self.add_sdn_unsuspension_staff_note(note: reason)
    true
  end

  sig { override.returns(T::Boolean) }
  def sdn_suspended?
    self.trade_screening_record.true_match? && self.suspended?
  end

  # Public: Move an organization's trade screening record over to the Business.
  # Only transfers if they have a valid CToS record.
  sig { params(organization: Organization).void }
  def transfer_trade_screening_record(organization)
    return unless organization.trade_screening_record.valid?(:entity)

    self.trade_screening_record = organization.trade_screening_record
    self.trade_screening_record.save!
  end

  sig { override.void }
  def send_sponsors_maintainer_restricted_email
    raise NotImplementedError
  end
end
