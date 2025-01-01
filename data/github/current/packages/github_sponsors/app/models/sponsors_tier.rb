# typed: true
# frozen_string_literal: true

class SponsorsTier < ApplicationRecord::Domain::Sponsors
  extend GitHub::Encoding

  include Workflow
  include GitHub::Relay::GlobalIdentification
  include Billing::Subscribable
  include SponsorsTier::ZuoraDependency
  include Instrumentation::Model

  MAX_NAME_LENGTH = 255
  MAX_DESCRIPTION_LENGTH = 750
  MAX_SPONSORSHIP_AMOUNT_DIGITS = 5 # The max number of digits in dollar amount, e.g. 10,000
  MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS = 12_000 # The max dollar amount allowed per monthly sponsorship transaction.
  MAX_SPONSORSHIP_AMOUNT_IN_CENTS = MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS * 100
  MAX_SPONSORSHIP_AMOUNT_HUMAN = MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS.to_formatted_s(:currency, precision: 0)
  PUBLISHED_TIER_LIMIT_PER_FREQUENCY = 10
  MIN_PRICE_IN_CENTS = 100 # $1.00

  enum :frequency, {
    recurring: 0,
    one_time: 1,
  }

  attribute :description, StringFromBinary.new
  attribute :name, StringFromBinary.new
  attribute :welcome_message, StringFromBinary.new

  belongs_to :sponsors_listing, required: true
  belongs_to :creator, class_name: "User"
  belongs_to :repository

  # parent_tier is only set for custom tiers. It is the closest lesser-or-equal-value published tier
  # of the same frequency, at the time of creation. It is used to know the tier rewards
  # the sponsor should receive.
  belongs_to :parent_tier, class_name: "SponsorsTier"

  has_one :sponsorable, through: :sponsors_listing, disable_joins: true

  has_many :sponsorships, foreign_key: :subscribable_id, inverse_of: :tier
  has_many :active_sponsorships, -> do
    T.bind(self, T.untyped)
    active
  end, foreign_key: :subscribable_id, inverse_of: :tier, class_name: "Sponsorship"
  has_many :sponsorship_repositories, inverse_of: :sponsors_tier

  has_many :subscription_items, class_name: "Billing::SubscriptionItem",
                                as: :subscribable,
                                inverse_of: :subscribable,
                                dependent: :restrict_with_error
  has_many :active_subscription_items, -> do
    T.bind(self, T.untyped)
    active
  end, class_name: "Billing::SubscriptionItem", as: :subscribable, inverse_of: :subscribable
  has_many :pending_subscription_item_changes, class_name: "Billing::PendingSubscriptionItemChange",
                                               as: :subscribable,
                                               dependent: :destroy

  has_many :sponsorship_newsletter_tiers, dependent: :destroy

  validates :name, :monthly_price_in_cents, :yearly_price_in_cents, presence: true
  validates :name, length: { maximum: MAX_NAME_LENGTH }
  validates :repository, presence: true, if: :repository_id
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }
  validates :description, presence: true, unless: :custom_or_invoiced?
  validates :monthly_price_in_cents, :yearly_price_in_cents, numericality: {
    only_integer: true,
    greater_than: 0,
  }
  validates :repository, presence: true, if: :require_repository

  validate :description_is_not_nil, if: :custom_or_invoiced?
  validate :name_can_be_changed, if: :name_changed?
  validate :tier_amount_can_be_changed
  validate :published_tier_count_limit
  validate :tier_amount_within_sponsorship_limit
  validate :published_tier_amount_is_unique_for_frequency, on: :create
  validate :published_tier_name_is_unique
  validate :monthly_price_in_cents_divisible_by_100
  validate :yearly_price_in_cents_divisible_by_100
  validate :creator_exists_if_necessary
  validate :parent_tier_not_set, unless: :custom?
  validate :parent_tier_is_for_the_same_listing
  validate :parent_tier_is_not_self
  validate :parent_tier_is_published, on: :create
  validate :parent_tier_does_not_exceed_price
  validate :parent_tier_matches_frequency
  validate :invoiced_tiers_have_one_time_frequency, if: :invoiced?
  validate :custom_amount_above_min
  validate :recurring_tier_for_sponsors_only_repository, if: :repository
  validate :non_custom_tier_for_sponsors_only_repository, if: :repository
  validate :sponsors_only_repository_is_valid, if: :repository

  alias_attribute :listing_id, :sponsors_listing_id

  def listing
    sponsors_listing
  end

  def listing=(value)
    self.sponsors_listing = value
  end

  def async_listing
    async_sponsors_listing
  end

  # Used to perform conditional validation
  attr_accessor :skip_max_amount_validation
  attr_accessor :require_repository

  scope :with_states, ->(*states) do
    state_values = states.map { |state| state_value(state) }
    where(state: state_values)
  end

  scope :for_listing, -> (listing_or_id) { where(sponsors_listing_id: listing_or_id) }

  scope :for_sponsorable, -> (sponsorable_or_id) do
    joins(:sponsors_listing)
      .merge(SponsorsListing.for_sponsorable_user_or_org([sponsorable_or_id]))
  end

  scope :highest_monthly_price_first, -> { order(monthly_price_in_cents: :desc) }
  scope :with_monthly_price_in_cents, -> (cents) { where(monthly_price_in_cents: cents) }
  scope :with_recurrence, -> (is_recurring) { where(frequency: is_recurring ? :recurring : :one_time) }
  scope :monthly_price_in_cents_at_most, -> (cents) { where(arel_table[:monthly_price_in_cents].lteq(cents)) }
  scope :monthly_price_in_dollars_at_most, -> (dollars) { monthly_price_in_cents_at_most(dollars * 100) }

  # Public: Get tiers that the maintainer (sponsorable) created, as opposed to those created by
  # GitHub staff or the sponsors.
  scope :sponsorable_defined, -> { with_states(:draft, :published, :retired) }

  scope :with_active_sponsorships, -> { where(id: Sponsorship.active.select(:subscribable_id)) }

  scope :includes_listings, -> {
    includes(:sponsors_listing)
  }

  scope :for_repository, -> (repository) { where(repository: repository) }

  # Public: Filter tiers to those readable by the given viewer.
  #
  # actor - a User or nil
  scope :visible_to, ->(actor) do
    base_query = joins(:sponsors_listing).left_joins(:sponsorships)
    publicly_visible_tiers = T.unsafe(base_query).with_published_state.merge(SponsorsListing.with_approved_state)
    return publicly_visible_tiers unless actor # anonymous viewer

    org_ids_for_actor = actor.potential_organization_sponsor_ids +
      actor.potential_linked_organization_sponsor_ids

    actor_tiers_as_sponsorable = base_query.merge(SponsorsListing.for_sponsorable_user_or_org([actor.id]))
    actor_tiers_as_sponsor_from_active_sponsorships = base_query.merge(Sponsorship.active.from_sponsor(actor.id))
    actor_created_custom_tiers = T.unsafe(base_query).with_custom_state.where(creator_id: actor.id)

    visible_tiers = publicly_visible_tiers
      .or(actor_tiers_as_sponsorable)
      .or(actor_tiers_as_sponsor_from_active_sponsorships)
      .or(actor_created_custom_tiers)

    if org_ids_for_actor.any?
      actor_org_subscription_tier_ids = Billing::SubscriptionItem.for_sponsors_tiers.for_plan_subscription(
        Billing::PlanSubscription.for_user(org_ids_for_actor).select(:id)
      ).pluck(:subscribable_id)

      if actor_org_subscription_tier_ids.any?
        actor_tiers_as_sponsor_from_subscriptions = base_query.where(id: actor_org_subscription_tier_ids)
        visible_tiers = visible_tiers
          .or(actor_tiers_as_sponsor_from_subscriptions) # will include concurrent one-time payments
      end

      actor_created_invoiced_tiers = T.unsafe(base_query).with_invoiced_state.where(creator_id: org_ids_for_actor)
      visible_tiers = visible_tiers
        .or(actor_created_invoiced_tiers) # legacy-style invoiced tiers
    end

    visible_tiers.distinct
  end

  # Public: Get tiers that are at or below the specified values but the same frequency, for the specified
  # Sponsors listings.
  #
  # sponsors_listing_ids - Array of SponsorsListing IDs whose tiers should be included
  # amounts - Array of Integer dollar amounts, each corresponding to the SponsorsListing ID at the same index
  # recurrings - Array of Booleans for whether the tier should be a recurring tier (true) versus one-time (false),
  #              each corresponding to the SponsorsListing ID at the same index
  scope :closest_lesser_value_tiers_for, -> (sponsors_listing_ids, amounts:, recurrings:) do
    if sponsors_listing_ids.any? && sponsors_listing_ids.size == amounts.size && amounts.size == recurrings.size
      base_query = with_published_state

      tiers = base_query.for_listing(sponsors_listing_ids.first)
        .with_recurrence(recurrings.first)
        .monthly_price_in_dollars_at_most(amounts.first)

      sponsors_listing_ids.each_with_index do |sponsors_listing_id, i|
        tiers = tiers.or(base_query.for_listing(sponsors_listing_id)
          .with_recurrence(recurrings[i]))
          .monthly_price_in_dollars_at_most(amounts[i])
      end

      tiers.highest_monthly_price_first
    else
      none
    end
  end

  delegate :sponsorable_id, to: :sponsors_listing
  delegate :owner_login, to: :repository, prefix: true

  workflow :state do
    # A tier being worked on by the sponsorable, not yet ready for the public to see
    # but with the goal of eventually being publicly visible and usable by multiple
    # sponsorships.
    state :draft, 0 do
      event :publish, transitions_to: :published, if: :can_be_published_for_listing?
    end

    # A publicly visible tier that can be used by many sponsorships. Represents a
    # dollar amount that was defined by the sponsorable.
    state :published, 1 do
      event :retire, transitions_to: :retired
    end

    # A once-published tier that is no now longer available for use in new sponsorships.
    # Can still be used in existing sponsorships that were active when the tier was
    # retired. This tier was defined by the sponsorable.
    state :retired, 2

    # A tier that is meant to be used with a single sponsorship, to support a custom
    # dollar amount. This tier was defined by the sponsor at checkout time, not ahead
    # of time by the sponsorable.
    state :custom, 3

    # Important: this state is only used for legacy invoiced sponsors.
    # Zuora-invoiced sponsors use normal published or custom tiers.
    #
    # A tier that is meant to represent and be used with a single invoiced sponsorship.
    # It acts similar to custom tiers in that they are defined by someone other than the
    # sponsorable at checkout time (currently done by GitHub staff for the sponsor).
    state :invoiced, 4
  end

  # Public: Get the Integer value matching a certain state.
  def self.state_value(name)
    workflow_spec.states[name.to_sym]&.value
  end

  # Public: Run the given tier description text through the Markdown processor.
  #
  # description - String of Markdown describing a Sponsors tier
  #
  # Returns a String of HTML.
  def self.description_html_for(description)
    context = { base_url: GitHub.url }
    GitHub::Goomba::SponsorsTierDescriptionPipeline.to_html(description, context, nil)
  end

  # Public: Are Sponsors subscription items for this account adminable by the user?
  #
  # sponsor - the account (User/Organization) with subscription items
  # actor - the User to check for adminability
  #
  # Returns a Boolean
  def self.subscription_items_adminable_by?(sponsor:, actor:)
    return false unless sponsor && actor
    return false unless actor.user?
    return true if sponsor == actor
    if sponsor.organization?
      return true if sponsor.billing_manageable_by?(actor)
      return true if actor.can_admin_sponsors_listings? && sponsor.sponsors_invoiced?
    end
    false
  end

  def to_s
    name
  end

  # Public: The billing cycle for this tier, if it should override the sponsor's
  # plan duration.
  #
  # Returns a Symbol or nil
  def billing_cycle
    :one_time if one_time?
  end

  # Public: Generate an appropriate name for this tier based on its cost and how
  # often the sponsor will be charged for choosing this tier.
  #
  # Returns a String.
  def generate_name
    price_in_cents = if invoiced?
      yearly_price_in_cents
    else
      monthly_price_in_cents
    end

    self.class.generate_name_for(price_in_cents, frequency)
  end

  # Public: Stateless utility method for converting price in cents and frequency
  # into human-readable string without instantiating this class.
  #
  # Accepts monthly price in cents as an integer, and frequency as a symbol [:recurring, :one_time]
  #
  # Returns a String.
  def self.generate_name_for(monthly_price_in_cents, frequency)
    if frequency.to_s == "recurring"
      "#{formatted_monthly_price(price: monthly_price_in_cents)} a month"
    else
      "#{formatted_monthly_price(price: monthly_price_in_cents)} one time"
    end
  end

  def stripe_transfers_enabled?
    sponsors_listing&.stripe_transfers_enabled?
  end

  # Public: Returns a symbol representing the current state of this tier.
  def current_state_name
    current_state.name
  end

  def async_pending_subscription_item_change(account:, organization: nil)
    # We get pending changes via the tier for a kinda esoteric reason. We record pending changes with no relation to
    # any subscription item so they can represent the desired state regardless of any current state. We also need to
    # ensure that we don't look only for changes with this tier as the subscribable since e.g. a pending downgrade
    # (pointing to a different subscribable/tier) is still considered a change to this tier.
    return Promise.resolve(nil) unless account

    pending_sub_item_changes_promise = if account.business?
      account.async_customer.then do |customer|
        customer.async_pending_subscription_item_changes
      end
    else
      account.async_pending_subscription_item_changes
    end

    pending_sub_item_changes_promise.then do |pending_sub_item_changes|
      sponsors_changes = pending_sub_item_changes.filter_map do |pending_sub_item_change|
        next unless pending_sub_item_change.subscribable_SponsorsTier?
        pending_sub_item_change
      end
      next unless sponsors_changes

      # Short-circuit in the standard case, where the lookup is a sponsorship cancellation
      change = sponsors_changes.find do |change|
        if organization && organization != account
          change.subscribable_id == id && change.organization_id == organization.id
        else
          change.subscribable_id == id
        end
      end
      next change if change.present?

      # Fall back to generating a mapping of the discovered pending sponsors subscription item changes keyed by a
      # lookup key that allows determining the relevant change for the given tier. Keying by the `listing_id` and
      # `organization_id` (if present). The `listing_id` narrows to match e.g. downgrades where the subscribable
      # differs, and the `organization_id` lets us resolve ambiguity in the case that multiple member orgs of an
      # enterprise account sponsor the same maintainer.
      pending_change_keys = sponsors_changes.map do |change|
        change.async_subscribable.then do |subscribable|
          [subscribable.sponsors_listing_id, change.organization_id]
        end
      end

      Promise.all(pending_change_keys).then do |change_keys|
        keyed_pending_sub_item_changes = change_keys.zip(sponsors_changes).to_h

        key = if organization && organization != account
          [sponsors_listing_id, organization.id]
        else
          [sponsors_listing_id, nil]
        end
        keyed_pending_sub_item_changes[key]
      end
    end
  end

  # Internal: Get a pending change for a tier
  #
  # account - the billable entity (User/Org/Business) for the tier
  # organization - (Optional) the managing entity for the tier, if it differs from the billable entity.
  #
  # Returns a Billing::PendingSubscriptionItemChange
  def pending_subscription_item_change(account:, organization: nil)
    return nil unless account.present?

    pending_tier_changes = account.pending_subscription_item_changes.for_sponsors_listing(sponsors_listing_id)
    if organization && organization != account
      pending_tier_changes.where(organization: organization).first
    else
      pending_tier_changes.first
    end
  end

  # Public: Can this tier be used in subscriptions?
  # We need this method to support Billing::Subscribable interface.
  def available_for_purchase?
    published? || custom?
  end

  # Public: Create a sponsorship-repository join record to indicate that the given sponsor should be granted access
  # to this tier's repository. Should only be called when this tier does have a repository specified.
  #
  # sponsor - a User or Organization
  #
  # Returns a SponsorshipRepository or raises ActiveRecord::RecordInvalid on failure.
  def create_sponsorship_repository(sponsor:)
    repo_id = repository_id_for_sponsor(sponsor)
    sponsorship_repositories.create!(sponsor: sponsor, repository_id: repo_id, sponsorable: sponsorable)
  end

  # Public: Is this tier one that a sponsor can have an active sponsorship for while also having an active
  # subscription for the other subscribable?
  #
  # other_subscribable - a Billing::Subscribable, like another SponsorsTier or a Marketplace::ListingPlan
  #
  # Returns a Boolean.
  def can_be_concurrent_with_subscription_item_for?(other_subscribable)
    return true if super(other_subscribable)
    frequency != other_subscribable.frequency
  end

  # Public: Can this tier be used to create sponsorships?
  def available_for_sponsorship?
    available_for_purchase? || invoiced?
  end

  def for_user?
    sponsorable&.user?
  end

  def for_organization?
    sponsorable&.organization?
  end

  # Public: This is always false for Sponsors tiers.
  # We need this method to support Billing::Subscribable interface.
  def per_unit?
    false
  end

  # Public: This is always false for Sponsors tiers.
  # We need this method to support Billing::Subscribable interface.
  def has_free_trial?
    false
  end

  # Public: Returns false as we support user-to-user and org-to-user sponsorships
  # Need this method to support Billing::Subscribable interface.
  def for_organizations_only?
    false
  end

  # Public: Returns false as we support user-to-user and org-to-user sponsorships
  # We need this method to support Billing::Subscribable interface.
  def for_users_only?
    false
  end

  # Public: Returns true if the pricing can still be changed for this tier.
  def can_change_pricing?
    draft?
  end

  # Public: Whether this tier can be published.
  def can_be_published_for_listing?
    return false unless sponsors_listing
    !T.must(sponsors_listing).reached_maximum_tier_count?(recurring: recurring?)
  end

  # Public: Get a published tier for the specified Sponsors listing, with the specified frequency, and with an equal
  # or lesser cost than the specified amount. Returns the tier with the monthly price closest to the specified amount
  # without going over it.
  #
  # amount - Integer amount in USD
  # is_recurring - whether the tier is for a recurring sponsorship or a one-time payment
  #
  # Returns a SponsorsTier or nil.
  def self.closest_lesser_value_tier_for(sponsors_listing_id, amount:, is_recurring:)
    closest_lesser_value_tiers_for([sponsors_listing_id], amounts: [amount], recurrings: [is_recurring]).first
  end

  # Public: Get a published tier for this listing at the same frequency as this
  # tier but with an equal or lesser cost. Returns the tier with the monthly price closest to
  # this tier's without going over this tier's.
  #
  # Examples:
  #
  #   # To prevent N+1s when this method is called on a list of SponsorsTier records, prefill it this way:
  #
  #   # Execute 1 query to preload (usually in a controller action):
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsors_tiers, :closest_lesser_value_tier)
  #
  #   sponsors_tiers.each do |tier|
  #     tier.closest_lesser_value_tier # Method is preloaded and memoized -- no queries are executed here!
  #   end
  #
  # Returns a SponsorsTier or nil.
  batch_method :closest_lesser_value_tier do |tiers|
    # Returned with the highest-value tiers first:
    all_closest_lesser_value_tiers = SponsorsTier.closest_lesser_value_tiers_for(
      tiers.map(&:sponsors_listing_id),
      amounts: tiers.map { |tier| tier.monthly_price_in_dollars.to_i },
      recurrings: tiers.map(&:recurring?),
    )
    closest_lesser_value_tiers_by_tier = all_closest_lesser_value_tiers.each_with_object({}) do |tier, hash|
      listing_key = tier.sponsors_listing_id
      recurring_key = tier.recurring?
      hash[listing_key] ||= {}
      hash[listing_key][recurring_key] ||= []
      hash[listing_key][recurring_key] << tier
    end
    tiers.each_with_object({}) do |tier, hash|
      hash_for_listing = closest_lesser_value_tiers_by_tier[tier.sponsors_listing_id] || {}
      tiers_at_recurrence = hash_for_listing[tier.recurring?] || [] # ordered by price descending
      max_price = tier.base_price
      closest_lesser_value_tier = tiers_at_recurrence
        .detect { |other_tier| other_tier.id != tier.id && other_tier.base_price <= max_price }
      hash[tier] = closest_lesser_value_tier
    end
  end

  # Public: Retrieve the repository that the given sponsor who chose this tier for their sponsorship should be granted
  # access to as a result of their sponsorship, if any.
  #
  # sponsor - a User, Organization, or nil; expected to be a sponsor using this tier
  #
  # Returns a Repository or nil.
  def repository_for_sponsor(sponsor)
    return unless grants_repository_access_to?(sponsor)
    repository || parent_or_closest_lesser_value_tier_repository
  end

  # Public: Retrieve the ID of the repository that the given sponsor who chose this tier for their sponsorship should
  # be granted access to as a result of their sponsorship, if any.
  #
  # sponsor - a User, Organization, or nil; expected to be a sponsor using this tier
  #
  # Returns an Integer or nil.
  def repository_id_for_sponsor(sponsor)
    repo = repository_for_sponsor(sponsor)
    repo&.id
  end

  # Public: Returns the User or Organization who should be the inviter when a sponsor at this tier is granted repository access.
  #
  # Returns a User or Organization
  def actor_for_repository_invitation
    sponsorable
  end

  # Public: Get the explicitly set parent tier for this tier, which may be published or now retired, or the currently
  # published tier that has the same frequency and a lesser-or-equal monthly cost as this tier.
  #
  # Returns a SponsorsTier or nil.
  def parent_or_closest_lesser_value_tier
    return @parent_or_closest_lesser_value_tier if defined?(@parent_or_closest_lesser_value_tier)
    @parent_or_closest_lesser_value_tier = parent_tier || closest_lesser_value_tier
  end

  # Public: Is an actor able to view this tier?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise<Boolean>.
  def async_readable_by?(actor)
    async_sponsors_listing.then do |listing|
      next true if publicly_visible?
      next false unless actor.present?

      async_creator.then do |creator|
        next true if custom_or_invoiced? && creator == actor

        async_invoiced_tier_adminable_by?(actor).then do |is_invoiced_tier_adminable_by_actor|
          next true if is_invoiced_tier_adminable_by_actor
          next true if actor.user? && sponsorship_exists_for?(actor)

          actor.async_plan_subscription.then do
            T.must(listing).async_adminable_by?(actor)
          end
        end
      end
    end
  end

  # Public: Check if the description of this tier should be visible to the given actor.
  # Assumes the actor has read access to this tier.
  #
  # actor - a User
  #
  # Returns a Promise resolving to a Boolean.
  def async_description_readable_by?(actor)
    if custom_or_invoiced?
      async_creator.then do |creator|
        next true if actor == creator

        async_invoiced_tier_adminable_by?(actor).then do |is_invoiced_tier_adminable_by_actor|
          next true if is_invoiced_tier_adminable_by_actor
          actor.user? && sponsorship_exists_for?(actor)
        end
      end
    else
      Promise.resolve(true)
    end
  end

  # Public: Check if a sponsorship exists for this Sponsors tier for the given user,
  # or for an organization the given user can billing manage.
  #
  # actor - a User or nil
  #
  # Returns a Boolean.
  def sponsorship_exists_for?(actor)
    return false unless actor

    sponsor_ids = actor.potential_sponsor_ids + actor.potential_linked_organization_sponsor_ids

    Sponsorship.from_sponsor(sponsor_ids).with_tier(self).exists?
  end

  def publicly_visible?
    published? && sponsors_listing&.approved?
  end

  # Public: Is an actor able to view this tier?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  # Public: Returns true if the given User has admin access to this plan
  def adminable_by?(actor)
    async_adminable_by?(actor).sync
  end

  def async_adminable_by?(actor)
    async_sponsors_listing.then do |listing|
      listing&.async_adminable_by?(actor)
    end
  end

  sig { params(other_tier: T.nilable(T.any(SponsorsTier, SponsorsPatreonTier))).returns(T::Boolean) }
  def equal_price?(other_tier)
    return false unless other_tier
    monthly_price_in_cents == other_tier.monthly_price_in_cents &&
      yearly_price_in_cents == other_tier.yearly_price_in_cents
  end

  # Public: Is this a custom tier for the same price, frequency, and listing as the given tier?
  #
  # other_tier - a SponsorsTier or nil
  #
  # Returns a Boolean.
  def equal_custom_tier?(other_tier)
    return false unless other_tier&.custom? && custom?
    return false unless equal_price?(other_tier)
    return false unless other_tier.frequency == frequency
    other_tier.sponsors_listing_id == sponsors_listing_id
  end

  # Public: Returns the base price for this plan/tier.
  # Overridden from Billing::Subscribable.
  #
  # args - hash of arguments used to determine the base price of the subscribable.
  # args[:duration] - Optional. The duration price to return, :month or :year. Defaults to :month.
  # args[:include_fees] - Optional Boolean. Whether to include sponsorship fees in the price.
  # args[:subscription_item] - A Billing::SubscriptionItem. Used to determine the fee for a specific sponsor.
  #
  # Returns a Billing::Money
  sig { override.params(args: T.untyped).returns(Billing::Money) }
  def base_price(**args)
    base_money = super(duration: args[:duration])
    return base_money unless args[:include_fees]

    subscription_item = args[:subscription_item]
    raise "Need a subscription item to determine the fee" unless subscription_item
    T.cast(subscription_item, Billing::SubscriptionItem)

    fee = subscription_item.sponsors_fee(base_money)
    base_money + fee
  end

  # Public: Returns true if the given User has permission to edit this tier.
  def editable_by?(actor)
    return false unless actor && sponsors_listing

    if custom_or_invoiced?
      # The author of a custom tier can set its details
      return true if actor == creator
      return true if invoiced_tier_adminable_by?(actor)

      # Allow other org admins to edit custom tier when the sponsor is an org
      actor.user? && sponsorship_exists_for?(actor)
    elsif retired?
      # Cannot edit a retired tier
      false
    else
      # Must be an admin of the Sponsors listing to set the details of a published or draft tier
      sponsors_listing&.editable_by?(actor)
    end
  end

  # Public: Returns true if the given User has permission to delete this tier.
  #   We only allow this while:
  #    - Tier is in Draft.
  #    - Listing is in Draft (published tiers may be deleted in this state).
  def deletable_by?(actor)
    return false if sponsors_listing&.approved? && (published? || retired?)

    editable_by?(actor)
  end

  def async_description_html
    return Promise.resolve(GitHub::HTMLSafeString::EMPTY) if description.blank?

    # Skip cache when tier isn't saved since there's no ID field to use in the cache key:
    return Promise.resolve(self.class.description_html_for(description)) if new_record?

    Platform::Loaders::Cache.fetch(description_html_cache_key) do
      self.class.description_html_for(description)
    end
  end

  def description_html
    async_description_html.sync
  end

  # Public: Get the raw welcome message for sponsors at this tier. Will either be this tier's own welcome message,
  # the welcome message for this tier's parent tier, or the welcome message for the present-day published tier of the
  # same frequency and equal-or-lesser value as this tier.
  #
  # Returns a String or nil.
  def welcome_message_markdown
    return welcome_message if welcome_message.present?

    # Only custom tiers can refer back to another tier to get the appropriate welcome message:
    return unless custom?

    parent_or_closest_lesser_value_tier&.welcome_message
  end

  # Public: The tier's welcome message as HTML.
  #
  # Returns a String.
  def welcome_message_html
    markdown = welcome_message_markdown
    return GitHub::HTMLSafeString::EMPTY unless markdown.present?
    GitHub::Goomba::MarkdownPipeline.to_html(markdown)
  end

  # Public: Whether this tier, the parent tier, or the closest published tier has a welcome message.
  #         Only looks at the parent tier and closest published tier if this is a custom tier.
  #
  # Returns a Boolean
  def has_welcome_message?
    welcome_message_markdown.present?
  end

  def event_context(prefix: event_prefix)
    {
      prefix => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def sponsors_count_on_tier
    subscription_items.active.count
  end

  def instrument_description_change(actor:)
    return unless should_instrument_description_change?

    # Audit log
    instrument :sponsored_developer_tier_description_update,
      prefix: :sponsors,
      actor: actor,
      previous_description: description_previously_was

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsored_developer_tier_description_update",
      actor: actor,
      listing: sponsors_listing,
      tier: self,
      current_tier_description: description,
      previous_tier_description: description_previously_was,
      sponsors_count_on_tier: sponsors_count_on_tier
    )
  end

  def instrument_repository_change(actor:)
    return unless repository_id_previously_changed?

    # Audit log
    instrument :update_tier_repository,
      prefix: :sponsors,
      actor: actor

    # Hydro
    GlobalInstrumenter.instrument("sponsors.update_tier_repository",
      tier: self,
      listing: sponsors_listing,
      old_repository: old_repository,
      repository: repository,
      sponsorable: sponsorable,
      total_active_sponsors: sponsors_count_on_tier,
      actor: actor,
      repository_owner: repository&.owner,
      old_repository_owner: old_repository&.owner,
    )
  end

  def instrument_welcome_message_change(actor:)
    return unless should_instrument_welcome_message_change?

    # Audit log
    instrument :update_tier_welcome_message,
      prefix: :sponsors,
      actor: actor

    # Hydro
    GlobalInstrumenter.instrument("sponsors.update_tier_welcome_message",
      tier: self,
      listing: sponsors_listing,
      sponsorable: sponsorable,
      total_active_sponsors: sponsors_count_on_tier,
      actor: actor,
    )
  end

  # Public: Returns a String representing this tier's monthly cost in whole dollars.
  #
  # e.g., 100 cents would return "$1"
  def formatted_monthly_price
    self.class.formatted_monthly_price(price: monthly_price_in_cents)
  end

  def self.formatted_monthly_price(price:)
    Billing::Money.new(price).format(no_cents: true)
  end

  # Public: Returna a String representing this tier's cost per cycle for the given User.
  #
  # e.g., 100 cents recurring returns "$1 a month" or "$1 a year" depending on the user's billing cycle.
  # 100 cents for a one-time tier returns "$1 one time"
  def formatted_price_per_cycle(sponsor:)
    price = price_in_cents_per_cycle(plan_duration: sponsor.sponsors_plan_duration)
    formatted_price = Billing::Money.new(price).format(no_cents: true)
    return "#{formatted_price} one time" if one_time?

    "#{formatted_price} a #{sponsor.sponsors_plan_duration}"
  end

  # Public: The total price in cents of this tier's cost per cycle for the given User
  #
  # plan_duration - a String of "month" or "year" representing the User's plan_duration
  #
  # A $5/month tier would return 500 for a one-time tier or for a monthly tier for a user on a monthly plan.
  # A $5/month tier would return 60_00 (500 * 12) for a monthly tier for a user on a yearly plan
  #
  # Returns an Integer
  def price_in_cents_per_cycle(plan_duration:)
    return monthly_price_in_cents if one_time?
    plan_duration == User::BillingDependency::MONTHLY_PLAN ? monthly_price_in_cents : yearly_price_in_cents
  end

  # Public: Returns how much a subscription to this Sponsors tier gives GitHub in
  # annual recurring revenue, in cents. Since there is no revenue cut for sponsors
  # tiers (vs Marketplace listing plans), this is always zero.
  def github_arr(cycle)
    0
  end

  def async_target_for_conditional_access
    async_sponsors_listing.then { |x| T.must(x).async_target_for_conditional_access }
  end

  def target_for_conditional_access
    sponsors_listing&.target_for_conditional_access
  end

  def instrument_publish(actor:)
    # Hydro
    GlobalInstrumenter.instrument("sponsors.tier_publish", actor: actor,
      listing: sponsors_listing, tier: self)
  end

  # Public: Returns a String to act as an adjective describing the frequency of this tier.
  def frequency_adjective
    one_time? ? "one-time" : "monthly"
  end

  def to_money
    Billing::Money.new(monthly_price_in_cents)
  end

  # Public: Get the repository this tier grants access to due to its parent tier or the published tier of the same
  # frequency whose value is at or below this tier's. Only applicable for custom tiers.
  #
  # Returns a Repository or nil.
  def parent_or_closest_lesser_value_tier_repository
    return unless custom?

    # If a parent tier is specified for this tier, that tier is the one we advertised to the sponsor at
    # sponsorship-creation time, so any repository on that parent tier is the one the sponsor should get access to:
    return T.must(parent_tier).repository if parent_tier

    closest_lesser_value_tier&.repository
  end

  # Public: Does this tier specify a repository that sponsors should get access to? Is this tier a custom amount
  # chosen by the sponsor at sponsorship-creation time and there was a published tier of the same frequency at equal
  # or lesser value that specifies a repository? Is this tier a custom amount chosen by the sponsor at
  # sponsorship-creation time and later a tier was published for the same frequency with an equal or lesser value
  # than this tier?
  #
  # Returns a Boolean.
  def has_repository?
    return true if repository.present?
    parent_or_closest_lesser_value_tier_repository.present?
  end

  # Public: Does this tier grant access to a private repository for the specified user or organization?
  #
  # sponsor - a User, Organization, or nil
  #
  # Returns a Boolean.
  def grants_repository_access_to?(sponsor)
    # Only allowing users to sponsor and get access to repositories today, so we don't have to answer the question
    # of "who in the sponsoring org gets access":
    return false unless sponsor&.user?

    has_repository?
  end

  # Public: Enqueues a job to invite a sponsor to access a repository associated to this tier, if this
  # tier has a repository.
  #
  # Returns nothing.
  def enqueue_grant_repository_access_job_for(sponsor_id)
    return unless has_repository? && persisted?
    repo_id = repository_id || parent_or_closest_lesser_value_tier_repository&.id
    GrantSponsorsOnlyRepositoryAccessJob.perform_later(
      sponsor_id,
      repo_id,
      T.must(id)
    )
  end

  # Public: Checks for sdn_disabled state for the sponsors listing to validate
  # before taking action on the tier such as display
  # SDN - Special Designated Nationals
  #
  # Returns a boolean
  def sdn_disabled?
    sponsors_listing&.sdn_disabled?
  end

  # Public: Checks for repository validation errors, if this tier has a repository.
  #
  # Returns an array of errors or an empty array.
  def sponsors_only_repository_errors
    if repository.nil?
      []
    else
      SponsorsTier::RepositoryValidator.new(repository: repository, sponsorable: sponsorable).errors
    end
  end

  def sponsorable_login
    return @sponsorable_login if defined?(@sponsorable_login)
    @sponsorable_login = if association(:sponsorable).loaded?
      sponsorable&.login
    else
      sponsors_listing&.sponsorable_login
    end
  end

  # Public: Returns Billing::Money representing the recurring price of this tier.
  #
  # sponsor - The User or Organization purchasing this tier.
  #
  # Returns a Billing::Money (which may be zero for one-time purchases)
  def renewal_price(sponsor:)
    return Billing::Money.zero if one_time?

    duration = sponsor.yearly_sponsors_plan? ? :year : :month
    base_price(duration: duration)
  end

  def renewal_price_with_fee(sponsor:)
    return Billing::Money.zero if one_time?

    base_price_with_fee(sponsor: sponsor)
  end

  def base_price_with_fee(sponsor:)
    duration = sponsor.yearly_sponsors_plan? ? :year : :month
    base_price = base_price(duration: duration)

    base_price + Sponsorship.fee_at_sponsorship_payment_time_for(sponsor: sponsor, flat_price: base_price)
  end

  # Public: Get a dollar amount for the initial price of this tier including fees, personalized for a given sponsor.
  #
  # sponsor - The User or Organization purchasing this tier.
  # sponsorship - The current Sponsorship for this tier's listing, if one exists.
  # prorated - Boolean indicating whether the initial price should be prorated.
  #
  # Returns a Billing::Money (which may be zero for downgrades)
  def price_with_fee(sponsor:, sponsorship: nil, prorated: true)
    Sponsors::TierPrice.call(
      sponsor: sponsor,
      current_tier: sponsorship&.tier,
      new_tier: self,
      prorated: prorated,
    )
  end

  # Public: Get a dollar amount for the initial price of this tier excluding fees, personalized for a given sponsor.
  #
  # sponsor - The User or Organization purchasing this tier.
  # sponsorship - The current Sponsorship for this tier's listing, if one exists.
  # prorated - Boolean indicating whether the initial price should be prorated.
  #
  # Returns a Billing::Money (which may be zero for downgrades)
  def price(sponsor:, sponsorship: nil, prorated: true)
    Sponsors::TierPrice.call(
      sponsor: sponsor,
      current_tier: sponsorship&.tier,
      new_tier: self,
      prorated: prorated,
      exclude_fees: true,
    )
  end

  def same_listing?(other_subscribable)
    other_subscribable.is_a?(self.class) && other_subscribable.sponsors_listing_id == sponsors_listing_id
  end

  # Public: Get a description of this tier for use on billing line items. Overridden from Billing::Subscribable.
  #
  # args - a Hash with the following keys:
  #   :invoice_item - optional Billing::Zuora::SubscribableInvoiceItem
  #
  # Returns a String, e.g., "sponsors-zkat - $5 per month - fee" or "sponsors-zkat $10".
  sig { override.params(args: T.untyped).returns(String) }
  def line_item_description(**args)
    invoice_item = T.let(
      args[:invoice_item], T.nilable(Billing::Zuora::SubscribableInvoiceItem)
    )
    if invoice_item&.sponsors_fee_charge?
      # Keep in sync with Billing::BillingTransaction::LineItem#sponsors_fee?
      "#{super} -#{SponsorsListing::ZuoraDependency::FEE_CHARGE_SUFFIX}"
    else
      super
    end
  end

  # Public: Does an organization manage the subscription to this tier?
  #
  # account - the billable entity responsible for payment
  #
  # Returns a Boolean
  def management_delegated_to_org?(account)
    account.business?
  end

  private

  def old_repository
    return @old_repository if defined?(@old_repository)
    old_repository_id = repository_id_previously_was
    @old_repository = if old_repository_id
      Repositories::Public.find_active!(old_repository_id)
    end
  end

  def description_html_cache_key
    description_hash = Digest::SHA256.hexdigest(description)
    "sponsors-tier-description:#{id}:#{description_hash}"
  end

  # Private: Validates that we're only specifying a parent tier on custom tiers, because custom tiers are the only
  # ones we need to record a reference tier for, to indicate the most relevant published tier of the same frequency
  # of the custom tier at the time the custom tier was created.
  def parent_tier_not_set
    errors.add(:parent_tier, "cannot be set for a non-custom tier") if parent_tier_id
  end

  # Private: Ensure if a parent tier is set, it is for the same maintainer as this tier.
  def parent_tier_is_for_the_same_listing
    return unless parent_tier && sponsors_listing

    unless same_listing?(parent_tier)
      errors.add(:parent_tier, "is for another Sponsors listing, #{T.must(parent_tier).sponsorable_login} " \
        "instead of #{sponsorable_login}")
    end
  end

  # Private: It makes no sense for a tier to refer back to itself as its parent, so ensure that doesn't happen.
  def parent_tier_is_not_self
    return unless parent_tier_id && persisted?
    errors.add(:parent_tier, "cannot be itself") if id == parent_tier_id
  end

  # Private: The parent tier is meant to be the closest priced tier of the same frequency that's published at the
  # time this tier is created, so make sure that the specified parent tier is actually published and thus one that
  # would be shown to the sponsor.
  def parent_tier_is_published
    return unless parent_tier
    errors.add(:parent_tier, "must be published") unless T.must(parent_tier).published?
  end

  # Private: If a parent tier is set, it's meant to be the tier whose rewards the sponsor should receive as part
  # of their custom sponsorship (which this tier represents, as it must be custom or it couldn't have a parent tier).
  # So that parent tier should be no more than the price of this tier, to ensure we aren't recording that the
  # maintainer needs to give more expensive rewards to this sponsor than what they paid for.
  def parent_tier_does_not_exceed_price
    return unless parent_tier && monthly_price_in_cents

    if T.must(parent_tier).monthly_price_in_cents > monthly_price_in_cents
      errors.add(:parent_tier, "cannot exceed #{formatted_monthly_price}")
    end
  end

  # Private: Ensure the parent tier is a one-time tier if this is a one-time custom tier, and similarly, if this is a
  # monthly tier, the specified parent tier must also be a monthly tier.
  def parent_tier_matches_frequency
    return unless parent_tier

    unless frequency == T.must(parent_tier).frequency
      errors.add(:parent_tier, "is a #{T.must(parent_tier).frequency_adjective} tier instead of " \
        "a #{frequency_adjective} tier")
    end
  end

  def creator_exists_if_necessary
    return if creator

    if new_record? || custom_or_invoiced?
      errors.add(:creator, "can't be blank")
    end
  end

  def invoiced_tiers_have_one_time_frequency
    return unless invoiced?
    return if one_time?

    errors.add(:frequency, "must be one-time for invoiced tiers")
  end

  def custom_amount_above_min
    return unless custom?
    return unless sponsors_listing
    return unless T.must(sponsors_listing).min_custom_tier_amount_in_cents

    min_custom_amount_in_cents = T.must(sponsors_listing).min_custom_tier_amount_in_cents || 0
    if monthly_price_in_cents < min_custom_amount_in_cents
      minimum_formatted = Billing::Money.new(min_custom_amount_in_cents).format(no_cents: true)
      errors.add(:monthly_price_in_cents, "must be at least #{minimum_formatted}")
    end
  end

  def recurring_tier_for_sponsors_only_repository
    errors.add(:repository, "can only be specified for recurring tiers") unless recurring?
  end

  def non_custom_tier_for_sponsors_only_repository
    errors.add(:repository, "cannot be specified for custom tiers") if custom?
  end

  def sponsors_only_repository_is_valid
    sponsors_only_repository_errors.each do |error|
      errors.add(:repository, error)
    end
  end

  def should_instrument_description_change?
    publicly_visible? &&
      description != description_previously_was
  end

  def should_instrument_welcome_message_change?
    publicly_visible? &&
      welcome_message&.strip != welcome_message_previously_was&.strip
  end

  def event_prefix() :sponsors_tier end

  def event_payload
    payload = {
      event_prefix => self,
      :state => current_state_name,
      :description => description,
      :welcome_message => welcome_message,
      :monthly_price_in_cents => monthly_price_in_cents,
      :yearly_price_in_cents => yearly_price_in_cents,
    }

    payload.merge!(T.must(sponsorable).event_context) if sponsorable
    payload.merge!(T.must(sponsors_listing).event_context) if sponsors_listing
    payload.merge!(T.must(repository).event_context) if repository
    payload.merge!(old_repository.event_context(prefix: :old_repo)) if old_repository
    payload
  end

  # Private: Ensures name is only changed when allowed
  def name_can_be_changed
    return if draft? || new_record?
    errors.add(:name, "cannot be changed for a #{current_state_name} tier")
  end

  def description_is_not_nil
    if description.nil?
      errors.add(:description, "can't be nil")
    end
  end

  # Private: Ensures tier amount is only changed when allowed
  def tier_amount_can_be_changed
    return if draft? || new_record?

    if monthly_price_in_cents_changed?
      errors.add(:monthly_price_in_cents, "cannot be changed for a #{current_state_name} tier")
    end
    if yearly_price_in_cents_changed?
      errors.add(:yearly_price_in_cents, "cannot be changed for a #{current_state_name} tier")
    end
  end

  def published_tier_count_limit
    return unless sponsors_listing && published?

    tiers_in_frequency = other_published_tiers(any_frequency: false)
    if tiers_in_frequency.count >= PUBLISHED_TIER_LIMIT_PER_FREQUENCY
      errors.add(:sponsors_listing,
        "has reached its limit for published, #{frequency_adjective} tiers")
    end
  end

  # Private: Ensures tier amount is within sponsorship limit
  def tier_amount_within_sponsorship_limit
    return unless self[:monthly_price_in_cents]
    return if invoiced? # 🤑
    return if skip_max_amount_validation

    if monthly_price_in_cents > SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_CENTS
      errors.add(
        :monthly_price_in_cents,
        "exceeds maximum tier amount of #{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}",
      )
    end
  end

  # Private: Ensures published one-time tiers have unique amount and published recurring
  # tiers have a unique amount.
  def published_tier_amount_is_unique_for_frequency
    return unless sponsors_listing && monthly_price_in_cents
    return unless draft? || custom?

    dupe_tiers = other_published_tiers(any_frequency: false)
      .where(monthly_price_in_cents: monthly_price_in_cents)

    if dupe_tiers.count > 0
      errors.add(:monthly_price_in_cents,
        "#{formatted_monthly_price} is already in use by a published, #{frequency_adjective} tier")
    end
  end

  # Private: Ensures each published tier for the sponsors listing has a unique name
  def published_tier_name_is_unique
    return unless sponsors_listing && published?

    # mysql collation is case-insensitive
    if total_other_published_tiers_with_same_name > 0
      errors.add(:name, "is already in use by a published tier")
    end
  end

  def total_other_published_tiers_with_same_name
    # Can change `self["name"]` to just `name` after https://github.com/github/sponsors/issues/2329
    # is complete:
    other_published_tiers(any_frequency: true).where(name: self["name"]).count
  end

  def monthly_price_in_cents_divisible_by_100
    return unless self[:monthly_price_in_cents]

    unless monthly_price_in_cents % 100 == 0
      errors.add(:monthly_price_in_cents, "must be a whole-dollar amount (no cents)")
    end
  end

  def yearly_price_in_cents_divisible_by_100
    return unless self[:yearly_price_in_cents]

    unless yearly_price_in_cents % 100 == 0
      errors.add(:yearly_price_in_cents, "must be a whole-dollar amount (no cents)")
    end
  end

  # Private: Get a scope for this listing's published tiers excluding this instance.
  #
  # any_frequency - Boolean indicating whether only published tiers in the same frequency as this
  #                 tier should be included (false)
  #
  # Returns an ActiveRecord::Relation of SponsorsTier.
  def other_published_tiers(any_frequency:)
    return SponsorsTier.none unless sponsors_listing
    tiers = T.must(sponsors_listing).published_sponsors_tiers
    tiers = tiers.where("id <> ?", id) if persisted?
    tiers = tiers.where(frequency: frequency) unless any_frequency
    tiers
  end

  def custom_or_invoiced?
    custom? || invoiced?
  end

  def invoiced_tier_adminable_by?(actor)
    return false unless invoiced?
    return false unless creator && T.must(creator).organization?
    owner_ids = T.cast(T.must(creator), Organization).direct_admin_ids
    owner_ids.include?(actor.id)
  end

  def async_invoiced_tier_adminable_by?(actor)
    return Promise.resolve(false) unless invoiced?

    async_creator.then do |creator|
      return false unless T.must(creator).organization?
      T.must(creator).async_adminable_by?(actor)
    end
  end
end
