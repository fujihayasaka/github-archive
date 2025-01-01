# typed: false
# frozen_string_literal: true

class Marketplace::ListingPlan < ApplicationRecord::Domain::Integrations
  class RetirementNotAllowed < Exception; end

  include GitHub::Relay::GlobalIdentification
  extend GitHub::Encoding
  self.table_name = "marketplace_listing_plans"
  force_utf8_encoding :description

  include Marketplace::ListingPlan::ZuoraDependency

  include Instrumentation::Model
  include Billing::Subscribable

  PLAN_LIMIT_PER_LISTING = 10
  NAME_MAX_LENGTH = 255
  DESCRIPTION_SPONSORABLE_MAX_LENGTH = 750
  UNIT_NAME_MAX_LENGTH = 30
  FLAT_RATE_PRICE_MODEL = "FLAT_RATE"
  FREE_PRICE_MODEL = "FREE"
  PER_UNIT_PRICE_MODEL = "per-unit"
  DIRECT_BILLING_PRICE_MODEL = "direct-billing"

  include Workflow

  # should come before has_many :subscription_items in order
  before_destroy :destroy_subscription_items_draft

  # rubocop:todo Rails/InverseOf
  belongs_to :listing, class_name: "Marketplace::Listing", foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_many :bullets, class_name: "Marketplace::ListingPlanBullet",
                     foreign_key: "marketplace_listing_plan_id"
  # rubocop:enable Rails/InverseOf

  has_many :billing_transaction_line_items,
    class_name: "Billing::BillingTransaction::LineItem",
    as: :subscribable,
    inverse_of: :subscribable

  has_many :subscription_items, -> { with_marketplace_listing_plans_type },
                                class_name: "Billing::SubscriptionItem",
                                as: :subscribable,
                                inverse_of: :subscribable,
                                dependent: :restrict_with_error
  has_many :pending_subscription_item_changes, class_name: "Billing::PendingSubscriptionItemChange",
                                               dependent: :destroy,
                                               as: :subscribable,
                                               inverse_of:  :subscribable

  enum :subscription_rules, { for_users_only: 1, for_organizations_only: 2 }

  validates :listing, :name, :description, :monthly_price_in_cents, :yearly_price_in_cents, presence: true
  validates :name, length: { in: 1..NAME_MAX_LENGTH }
  validates :unit_name, length: { maximum: UNIT_NAME_MAX_LENGTH }, allow_blank: true
  validate :name_can_be_changed, if: :name_changed?
  validate :pricing_can_be_changed
  validate :unit_name_set_if_per_unit
  validate :not_at_plan_limit
  validate :direct_billing_allowed, if: :direct_billing?
  validate :prices_are_allowed
  validate :free_trial_is_allowed
  validate :unit_is_allowed
  validate :must_be_free_or_paid
  validate :published_plan_name_is_unique

  validates_inclusion_of :has_free_trial, in: [true, false]

  validates :monthly_price_in_cents, \
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 999_999_999,
  }
  validates :yearly_price_in_cents, \
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 999_999_999,
  }

  before_validation :set_number!, on: :create

  workflow :state do
    state :draft, 2 do
      event :publish, transitions_to: :published, if: :can_be_published_for_listing?
    end

    state :published, 0 do
      event :retire, transitions_to: :retired
    end

    state :retired, 1

    on_transition do |_from, to, _event, *_args, **_kwargs|
      MarketplaceListingPlanZuoraSyncJob.perform_later(self) if to == :published
    end

    after_transition do |_from, to, _event, *_args|
      listing.set_filter_categories! if [:published, :retired].include?(to)
    end
  end

  # Public: Select Marketplace::ListingPlans that have a free trial.
  scope :with_free_trial, ->(state: nil) do
    criteria = { has_free_trial: true }
    criteria[:state] = state_value(state) if state
    where(criteria)
  end

  alias_attribute :listing_id, :marketplace_listing_id

  # Public: Whether this plan can be published.
  def can_be_published_for_listing?
    return false if listing.reached_maximum_plan_count?
    if paid?
      profile_location = Profile.find_by(user_id: self.listing.owner.id).try(:location)
      return false if Marketplace::Listing::RESTRICTED_REGIONS.include?(profile_location)
    end
    !paid? || listing.published_paid_plans_allowed?
  end

  # Public: User-facing error messages explaining why the plan cannot be published
  def unpublishable_reason
    return if draft? && can_publish?
    return "This plan has already been published." if published?
    return "This plan has been retired." if retired?
    error_messages = [].tap do |messages|
      if listing.reached_maximum_plan_count?
        messages << "the listing has reached the limit of published plans"
      end

      if paid? && !listing.published_paid_plans_allowed?
        messages << "the listing must have to complete required checks to have published paid plans"
      end
    end

    "This plan cannot be published: #{error_messages.join(", ")}"
  end

  # Get the Integer value matching a certain state.
  def self.state_value(name)
    workflow_spec.states[name.to_sym].value
  end

  # Returns all paid plans.
  scope :paid, -> { where("monthly_price_in_cents > 0 OR yearly_price_in_cents > 0") }

  scope :free, -> { where(monthly_price_in_cents: 0, yearly_price_in_cents: 0) }

  scope :includes_listings, -> {
    includes(:listing)
  }

  # Public: Returns true if the given User has permission to edit this plan.
  def allowed_to_edit?(actor)
    listing && listing.allowed_to_edit?(actor) && !retired?
  end

  # Public: Returns true if the given User has permission to delete this plan.
  #   We only allow this while:
  #    - Plan is in Draft.
  #    - Listing is in Draft (published plans may be deleted in this state).
  def allowed_to_delete?(actor)
    return false if listing && listing.publicly_listed? && (published? || retired?)

    allowed_to_edit?(actor)
  end

  # Public: Returns true if the given User has admin access to this plan
  def adminable_by?(actor)
    listing && listing.adminable_by?(actor)
  end

  def can_be_installed?
    published?
  end

  # Public: Can this listing plan be used in subscriptions?
  # We need this method to support Billing::Subscribable interface.
  def available_for_purchase?
    published?
  end

  # Public: Returns true if the name can still be changed for this plan.
  def can_change_name?
    draft?
  end

  # Public: Returns true if the pricing can still be changed for this plan.
  def can_change_pricing?
    draft?
  end

  # Public: Returns true if this plan should be visible.
  def visible_to?(actor)
    listing && listing.visible_to?(actor)
  end

  # Public: Returns a human-readable description of the kind of listing this plan is for.
  def listing_type
    listing.integratable_description
  end

  # Public: Returns true when the listing is still a draft.
  def draft_listing?
    listing && listing.draft?
  end

  # Public: Returns a string summarizing the price model of this plan.
  def price_model
    return DIRECT_BILLING_PRICE_MODEL if direct_billing?
    return FREE_PRICE_MODEL unless paid?
    return PER_UNIT_PRICE_MODEL if per_unit?
    FLAT_RATE_PRICE_MODEL
  end

  # Public: Returns true when prices can be set for this plan
  def prices_allowed?
    price_model.in?([PER_UNIT_PRICE_MODEL, FLAT_RATE_PRICE_MODEL])
  end

  # Public: Returns true when this plan can have a free trial
  def free_trial_allowed?
    price_model.in?([PER_UNIT_PRICE_MODEL, FLAT_RATE_PRICE_MODEL])
  end

  # Public: Returns true when a unit can be set for this plan
  def unit_allowed?
    price_model == PER_UNIT_PRICE_MODEL
  end

  # Public: Returns an integer count of how many more bullets can be added
  # to this listing plan.
  def remaining_bullet_count
    Marketplace::ListingPlanBullet::BULLET_LIMIT_PER_LISTING_PLAN - bullets.count
  end

  # Public: whether this plan can be retired or not.
  #
  # Plans can be retired if there is at least one other published plan.
  def can_be_retired?
    other_published_plans = self.class.
      with_published_state.
      where(marketplace_listing_id: marketplace_listing_id).
      where("id != ?", id)

    other_published_plans.any?
  end

  def pending_subscription_item_change(account:, organization: nil)
    return unless account

    marketplace_changes = account.pending_subscription_item_changes.for_organization(organization).subscribable_Marketplace_ListingPlan
    return unless marketplace_changes.present?

    listing_plan_ids = listing.listing_plan_ids.to_set

    marketplace_changes.detect do |change|
      listing_plan_ids.include?(change.subscribable_id)
    end
  end

  def async_pending_subscription_item_change(account:, organization: nil)
    return Promise.resolve(nil) unless account

    account = account.customer if account.business?
    account.async_pending_subscription_item_changes.then do |changes|
      next unless changes.present?

      async_listing.then do |listing|
        changes.detect do |change|
          # Is the listing_plan associated with this change a member of the same parent listing
          # as the subscription item @object?
          change.subscribable_Marketplace_ListingPlan? &&
            listing.listing_plans.where(id: change.subscribable_id).any? &&
              change.organization_id == organization&.id
        end
      end
    end
  end

  def event_prefix
    :marketplace_listing_plan
  end

  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      prefix => name,
    }
  end

  # Public: Creates an audit log event for this plan's creation with the given User as the actor.
  def instrument_create(actor:)
    instrument :create, actor: actor
  end

  # Public: Creates an audit log event for this plan's update with the given User as the actor.
  def instrument_update(actor:)
    instrument :update, actor: actor
  end

  # Public: Creates an audit log event for retiring this plan.
  def instrument_retire(actor:)
    instrument :retire, actor: actor
  end

  # Public: Creates an audit log event for publishing this plan.
  def instrument_publish(actor:)
    instrument :publish, actor: actor
  end

  def platform_type_name
    "MarketplaceListingPlan"
  end

  # Public: Returns how much a subscription to this listing plan gives GitHub in
  # annual recurring revenue, in cents.
  def github_arr(cycle:, quantity: 1)
    price_in_cents = if cycle == User::BillingDependency::MONTHLY_PLAN
      monthly_price_in_cents * 12
    else
      yearly_price_in_cents
    end

    (Billing::BillingTransaction.marketplace_revenue_cut * price_in_cents).floor * quantity
  end

  # Public: Determine whether the viewer can see this object, excluding integrations and oauth apps
  #
  # See https://github.com/github/marketplace/blob/master/docs/graphql-permissions.md for
  # more context around this implementation.
  def async_can_user_see?(user)
    async_listing.then do |listing|
      if published? && listing&.publicly_listed?
        true
      elsif user.nil?
        false
      elsif listing && user.user_or_org_account_has_purchased_listing?(listing)
        true
      elsif user.can_admin_marketplace_listings?
        true
      elsif listing
        listing.async_owner.then do |owner|
          allowed_ids = owner.user? ? [owner.id] : owner.direct_admin_ids
          allowed_ids.include?(user.id)
        end
      else
        false
      end
    end
  end

  def can_user_see?(user)
    async_can_user_see?(user).sync
  end

  def same_listing?(other_subscribable)
    other_subscribable.is_a?(self.class) && other_subscribable.marketplace_listing_id == marketplace_listing_id
  end

  # Public: Does an organization manage the subscription to this listing plan?
  #
  # account - the billable entity responsible for payment
  #
  # Returns a Boolean
  def management_delegated_to_org?(account)
    account.business?
  end

  private

  def event_payload
    {
      marketplace_listing_plan: self,
      marketplace_listing: self.listing,
      listing_state: self.listing.current_state.name,
      state: current_state.name,
      description: description,
      bullets: self.bullets.pluck(:value),
      monthly_price_in_cents: monthly_price_in_cents,
      yearly_price_in_cents: yearly_price_in_cents,
      has_free_trial: has_free_trial,
      unit_name: unit_name,
    }
  end

  # This is called by workflow when transitioning to a :retired state.
  #
  # We could instead include :can_be_retired? when defining the state
  # transition, but that would raise a TransitionNotAllowed exception
  # without surfacing the reason that a plan can't be retired.
  def retire(actor: nil, **args)
    raise RetirementNotAllowed.new("Can't retire the only published plan.") unless can_be_retired?
    instrument_retire(actor: actor)
  end

  def publish(actor: nil, **args)
    instrument_publish(actor: actor)
  end

  def not_at_plan_limit
    return unless listing && published?

    if other_published_plans.count >= PLAN_LIMIT_PER_LISTING
      errors.add(:listing, "has reached its limit for payment plans")
    end
  end

  def direct_billing_allowed
    return unless listing
    return if listing.direct_billing_enabled?

    errors.add(:price_model, "listing cannot have direct billing plans")
  end

  def unit_name_set_if_per_unit
    return unless per_unit?

    if unit_name.blank?
      errors.add(:unit_name, "must be set if price model is 'per unit'")
    end
  end

  # Private: Ensures that both columns are either free, or have value.
  def must_be_free_or_paid
    return unless monthly_price_in_cents && yearly_price_in_cents
    unless monthly_price_in_cents.zero? == yearly_price_in_cents.zero?
      key = monthly_price_in_cents.zero? ? :yearly_price_in_cents : :monthly_price_in_cents
      if key == :yearly_price_in_cents
        errors.add key, "must be zero since the monthly price is zero, or choose free pricing model"
      else
        errors.add key, "must be zero since the yearly price is zero, or choose free pricing model"
      end
    end
  end

  # Private: Ensures each published plan for the listing has a unique name
  def published_plan_name_is_unique
    return unless listing && published?

    # mysql collation is case-insensitive
    if other_published_plans.where(name: name).count > 0
      errors.add(:name, "is already in use by a published plan")
    end
  end

  # Private: Get a scope for this listing's published plans excluding this instance.
  def other_published_plans
    plans = listing.listing_plans.with_published_state
    plans = plans.where("id <> ?", id) if persisted?
    plans
  end

  # Private: Set the plan number to the next sequence for this listing
  def set_number!
    return unless listing
    Sequence.create(listing) unless Sequence.exists?(listing)
    self.number = Sequence.next(listing)
  end

  # Private: Ensures name is only changed when allowed
  def name_can_be_changed
    return if can_change_name? || new_record?

    errors.add :name, "name cannot be changed for a published plan"
  end

  # Private: Ensures pricing is only changed when allowed
  def pricing_can_be_changed
    return if can_change_pricing? || new_record?

    [:monthly_price_in_cents, :per_unit, :unit_name, :yearly_price_in_cents].each do |pricing_attr|
      errors.add(pricing_attr, "cannot be changed for a published plan") if public_send("#{pricing_attr}_changed?")
    end
  end

  # Private: Ensures that prices are allowed for the plan
  def prices_are_allowed
    return if prices_allowed?

    errors.add(:monthly_price_in_cents, "must be zero for price model") unless monthly_price_in_cents == 0
    errors.add(:yearly_price_in_cents, "must be zero for price model") unless yearly_price_in_cents == 0
  end

  # Private: Ensures that free trials are allowed for the plan
  def free_trial_is_allowed
    return if free_trial_allowed? || !has_free_trial?

    errors.add(:has_free_trial, "is only allowed for paid plans")
  end

  # Private: Ensures that unit attributes are allowed for the plan
  def unit_is_allowed
    return if unit_allowed?

    errors.add(:per_unit, "is not allowed for price model") if per_unit?
    errors.add(:unit_name, "cannot be set if price model is not 'per unit'") unless unit_name.nil?
  end

  # Private: Destroy subscription_items for draft listing
  # it is required to remove listing plans because of condition dependent: :restrict_with_error on subscription_items
  def destroy_subscription_items_draft
    return if !listing.draft?
    subscription_items.destroy_all
  end
end
