# typed: strict
# frozen_string_literal: true

# A CustomerAccount provides a relationship between a Customer (someone we bill)
# and a user/org account. User's must verify their relationship with a customer
# and for organizations a member of the owners team must verify the org <->
# customer relationship.
class CustomerAccount < ApplicationRecord::Domain::Users

  # Public: The owning Customer record that will be paying for the
  # User/Organization.
  belongs_to :customer
  validates_presence_of :customer_id

  # Public: Represents the billing purpose of this customer account, like what kind of purchases the Zuora customer is
  # intended to be used for.
  enum :purpose, {
    general:  0, # any and all billing
    sponsors: 1, # sponsorships only
  }, suffix: true

  # Public: The User/Organization that the Customer is paying for.
  belongs_to :user
  validates_presence_of :user_id
  validates :user_id, uniqueness: { scope: :purpose }
  validate :purpose_matches_customer_purpose

  # Public: Alias for user because usually these are organizations.
  sig { returns(T.nilable(Organization)) }
  def organization
    T.cast(user, Organization) if user&.organization?
  end

  sig { params(org: T.nilable(Organization)).void }
  def organization=(org)
    self.user = org
  end

  after_destroy :clean_up_customer

  # Customer accounts by user/org login name.
  scope :sort_by_name, lambda { |direction|
    direction = "desc" unless direction == "asc"
    order("users.login #{direction}").includes(:user)
  }

  # Public: The User (must be a User) that verified the Customer <->
  # Organization relationship. Can be nil if CustomerAccount is not verified.
  belongs_to :verified_by, class_name: "User"

  # Public: State of this CustomerAccount.
  # column :state
  #   :unverified - A request has been made to associate the user/org with a
  #                 Customer, but the relationship has not been approved or
  #                 verified.
  #   :verified   - The user/org has been verified as associated with the Customer.
  enum :state, { unverified: 0, verified: 1 }
  validates :state, presence: true

  # Public: String token used to verify this customer account.
  # column :verification_token
  validates_presence_of   :verification_token, unless: :verified?

  # Public: String of this CustomerAccount's verification token.
  #
  # Returns a random hex String if not already set and nil if the
  # CustomerAccount is already verified.
  sig { returns(T.nilable(String)) }
  def verification_token
    return if verified?
    self[:verification_token] ||= SecureRandom.hex(10)
  end

  # Public: Verify this CustomerAccount with a token.
  #
  # token - Verification token to match up.
  # actor - The verifying user.
  #
  # Returns self or nil if the token can't be verified.
  sig { params(token: T.nilable(String), actor: T.nilable(User)).returns(T.nilable(T.self_type)) }
  def verify(token, actor)
    return unless token
    return unless verification_token == token
    return unless verifiable_by?(actor)

    verify!(actor)
  end

  # Public: Immediatly verify a CustomerAccount.
  #
  # actor - The verifying User
  #
  # Returns The CustomerAccount
  sig { params(actor: T.nilable(User)).returns(T.self_type) }
  def verify!(actor)
    self.verification_confirmed_at = Time.current
    self.verified_by = actor
    self.state = :verified

    save!

    self
  end

  # Public: Boolean if this account can be verified by an actor
  #
  # actor - The verifying User.
  #
  # Returns truthy if actor has permission to verify this account.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def verifiable_by?(actor)
    !!(actor == user || (organization&.adminable_by?(actor)) || actor&.site_admin?)
  end

  # Public: DateTime when CustomerAccount was verified. Can be nil if Account is
  # not verified.
  # column :verification_confirmed_at

  private

  sig { void }
  def purpose_matches_customer_purpose
    customer = self.customer
    return unless customer
    unless purpose == customer.purpose
      errors.add(:purpose, "must be #{customer.purpose} to match customer")
    end
  end

  # Internal: Removes the associated Customer if there are no
  # more customer accounts associated.
  # Don't destroy the customer if a Business is still attached to it.
  sig { void }
  def clean_up_customer
    customer = self.customer
    return unless customer
    return unless customer.customer_accounts.empty?
    return if customer.business.present?

    customer.destroy
  end
end
