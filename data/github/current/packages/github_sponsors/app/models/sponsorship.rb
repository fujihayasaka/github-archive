# typed: true
# frozen_string_literal: true

class Sponsorship < ApplicationRecord::Domain::Sponsors
  extend T::Sig
  include GitHub::Validations

  self.table_name = "sponsorships"

  # Public: Percent of the sponsorship payment we retain as GitHub as a service fee.
  PERCENT_SERVICE_FEE = 3

  # Public: Percent of the sponsorship payment we retain as GitHub as a transaction fee
  # for credit card payments.
  PERCENT_TRANSACTION_FEE = 3

  # Public: Percent of the sponsorship payment we retain as GitHub for organizations paying via credit card.
  # This fee is charged at the time of transaction (sponsorship creation and renewal).
  PERCENT_SPONSORSHIP_FEE_FOR_CREDIT_CARD_ORGS = PERCENT_SERVICE_FEE + PERCENT_TRANSACTION_FEE

  # Public: Percent of the sponsorship payment we retain as GitHub for organizations paying via invoice.
  # This fee is charged manually at time of invoice, and is excluded from their credit balance.
  PERCENT_SPONSORSHIP_FEE_FOR_INVOICED_ORGS = PERCENT_SERVICE_FEE

  # Public: The day Sponsors for Companies is shipped and the whole Sponsors program is out of beta.
  SPONSORS_PUBLIC_RELEASE_DATE = Date.new(2023, 4, 4)
  SPONSORS_PUBLIC_RELEASE_DATE_TEXT = SPONSORS_PUBLIC_RELEASE_DATE.strftime("%B %-d, %Y")

  # Public: The day we start applying fees to existing recurring sponsorships that were grandfathered-in because they
  # started before the public release date above
  SPONSORS_FEES_FOR_EXISTING_SPONSORSHIPS_DATE = Date.new(2023, 7, 1)
  SPONSORS_FEES_FOR_EXISTING_SPONSORSHIPS_DATE_TEXT = SPONSORS_FEES_FOR_EXISTING_SPONSORSHIPS_DATE.strftime("%B %-d, %Y")

  # Public: How many days does a one-time sponsorship remain locked to give time for
  # Zuora processing?
  LOCK_CUTOFF_IN_DAYS = 2

  # Public: How many days should a sponsor be listed as a sponsor on the maintainer's
  # Sponsors profile after they made a one-time payment to the maintainer? This is
  # inclusive.
  DAYS_TO_SHOW_ONE_TIME_SPONSORS = 30

  # Public: These fields are ones that are still able to be changed when #locked? is true,
  # because these fields do not impact Zuora being able to process the payment.
  CHANGEABLE_FIELDS_WHILE_LOCKED = %w(privacy_level updated_at expires_at
    is_sponsor_opted_in_to_email maintainer_notes is_sponsor_tier_reward_fulfilled
    is_sponsor_opted_in_to_share_with_fiscal_host active).freeze

  include Workflow
  include GitHub::Relay::GlobalIdentification
  include SponsorsListing::SponsorableMetadata
  include Sponsorship::InstrumentationDependency
  include Sponsorship::StateDependency

  # Public: Used to specify who is creating the sponsorship for use in #instrument_sponsorship_start.
  attr_accessor :actor

  enum :privacy_level, {
    public: 0,
    private: 1,
  }, prefix: :privacy

  enum :payment_source, {
    github: 0,
    patreon: 1
  }

  scope :active, -> { where(active: true).not_expired }
  scope :inactive, -> { where(active: false).or(expired) }

  # Public: returns all sponsorships that are pending, which means they have not expired and they
  # have not been paid. This scope is governed by the Sponsorship::StateDependency.
  scope :processing, -> { with_pending_state.unpaid.not_expired }

  # Public: returns all sponsorships that have active set to true and have been paid. This
  # scope is temporary and governed by the Sponsorship::StateDependency.
  # Issue 4692: https://github.com/github/sponsors/issues/4692
  #TODO: transition this scope to only use state once the `active` column is removed.
  scope :active_test, -> { where(active: true).or(with_active_test_state).paid.not_expired }

  # Public: returns all sponsorships that either have active set to false or have expired. This
  # scope is temporary and governed by the Sponsorship::StateDependency.
  # Issue 4691: https://github.com/github/sponsors/issues/4691
  #TODO: transition this scope to only use state once the `active` column is removed.
  scope :inactive_test, -> { with_inactive_test_state.or(inactive) }

  scope :listing_approved, -> { join_sponsors_listings_on_sponsorable.merge(SponsorsListing.with_approved_state) }

  scope :expired, -> { where(expires_at: ...Date.current) }

  # Public: Returns all sponsorships that have not yet expired, either because they have no concept
  # of expiration (when they use a recurring tier) or the expiration hasn't happened (invoiced
  # sponsorships and sponsorships with a one-time tier when the expiration is in the future).
  scope :not_expired, -> { where(expires_at: nil).or(where(expires_at: Date.current..)) }

  scope :emailable, -> { where(is_sponsor_opted_in_to_email: true) }

  # Public: Filter sponsorships to those whose tier was chosen on or after the given
  # time.
  scope :tier_selected_since, ->(datetime) do
    has_subscribable_selected_at.where(subscribable_selected_at: datetime..)
  end

  # Public: Get sponsorships using the specified Sponsors tier.
  scope :with_tier, ->(tier) { where(subscribable_id: tier) }

  scope :has_subscribable_selected_at, -> { where.not(subscribable_selected_at: nil) }

  scope :tier_selected_before, ->(datetime) { where(subscribable_selected_at: ...datetime) }

  scope :paid, -> { where(paid: true) }
  scope :unpaid, -> { where(paid: false) }
  scope :paid_or_patreon, -> { paid.or(patreon) }

  scope :active_or_paid, -> { paid_or_patreon.or(active) }

  scope :for_plan_subscription, ->(plan_subscription) do
    subscription_item_ids = Billing::SubscriptionItem.for_sponsors_tiers
      .for_plan_subscription(plan_subscription).pluck(:id)
    where(subscription_item_id: subscription_item_ids)
  end

  # Public: One-time sponsorships are those with a one-time tier. They represent
  # one-time payments to a maintainer.
  scope :one_time, -> { joins(:tier).merge(SponsorsTier.one_time) }

  # Public: Recurring sponsorships are those with a recurring tier. They represent
  # payments that happen periodically to the maintainer, based on the sponsor's
  # billing cycle (monthly or yearly).
  scope :recurring, -> { joins(:tier).merge(SponsorsTier.recurring) }

  # Public: Invoiced sponsorships have a one-time frequency associated with an
  # invoiced transfer. They are not associated with a Zuora subscription item.
  #
  # Please note that this scope is being deprecated, as automated support for invoiced sponsorships
  # will no longer use InvoicedSponsorshipTransfers. Please use the for_plan_subscription scope unless you
  # are specifically referring to manually-created sponsorships that use InvoicedSponsorshipTransfers
  scope :invoiced, -> { where.not(invoiced_sponsorship_transfer_id: nil) }

  scope :not_invoiced, -> { where(invoiced_sponsorship_transfer_id: nil) }

  # Public: Locked sponsorships use one-time tiers and had that tier chosen within
  # the last couple of days and haven't yet been deactivated, meaning they're
  # potentially still processing on Zuora and so some fields shouldn't be changed.
  # One-time invoiced sponsorships are not locked.
  scope :locked, -> do
    one_time.tier_selected_since(LOCK_CUTOFF_IN_DAYS.days.ago).not_invoiced
      .where(active: true)
  end

  scope :without_custom_tiers, -> do
    joins(:tier).where("sponsors_tiers.state <> ?", SponsorsTier.state_value(:custom))
  end

  scope :only_custom_tiers, -> do
    joins(:tier).merge(SponsorsTier.with_custom_state)
  end

  # These ranking scopes are very similar, and are implemented separately
  # to reduce confusion.
  scope :ranked_by_sponsor, ->(for_user:) {
    return scoped unless for_user

    target_attr = :sponsor_id

    public_user_ids = User.where(id: privacy_public.distinct.pluck(target_attr)).pluck(:id)
    ranked_ids = T.unsafe(User).ranked_for_ids(for_user, scoped_ids: public_user_ids)

    return scoped.order(target_attr) if ranked_ids.empty?

    field_clause = "FIELD(sponsorships.#{target_attr}, #{ranked_ids.join(", ")})"
    scoped.order(Arel.sql("IF(#{field_clause} = 0, 1, 0), #{field_clause}"))
      .order(target_attr)
  }

  # Public: Filter sponsorships so those from spammy sponsors and spammy sponsorables
  # will be excluded. Include this scope last in your query chain so that the smallest possible
  # set of user IDs has to be filtered.
  #
  # viewer - the currently authenticated User; may be nil
  #
  # Returns an ActiveRecord::Relation of Sponsorship.
  scope :filter_spam_for, ->(viewer) do
    # Either spamminess isn't a thing, so don't filter sponsorships based on that, or
    # the viewer is GitHub staff who can see spammers, so we don't need to filter out spammy sponsorships:
    return scoped if !GitHub.spamminess_check_enabled? || viewer&.site_admin?

    spammy_user_ids = spammy_user_ids_in_scope_excluding_viewer(scoped, viewer: viewer)
    return scoped if spammy_user_ids.empty? # no spammers detected, so no filtering needs to happen

    where.not(sponsor_id: spammy_user_ids).where.not(sponsorable_id: spammy_user_ids)
  end

  # Public: Get a list of IDs of the spammy users and organizations who are either sponsors or sponsorables
  # in the given sponsorship scope.
  #
  # sponsorship_scope - an ActiveRecord::Relation of Sponsorship
  # viewer - the currently authenticated User or nil
  sig { params(sponsorship_scope: ActiveRecord::Relation, viewer: T.nilable(User)).returns(T::Array[Integer]) }
  def self.spammy_user_ids_in_scope_excluding_viewer(sponsorship_scope, viewer:)
    user_ids = sponsorship_scope.pluck(:sponsor_id, :sponsorable_id).flatten.uniq
    user_scope = User.where(id: user_ids).spammy

    # If the viewer is a spammer themselves, want to still show their sponsorships to them:
    user_scope = user_scope.where.not(id: viewer.id) if viewer

    user_scope.pluck(:id)
  end

  scope :ranked_by_sponsorable, ->(for_user:) {
    return scoped unless for_user

    target_attr = :sponsorable_id

    public_user_ids = User.where(id: privacy_public.distinct.pluck(target_attr)).pluck(:id)
    ranked_ids = T.unsafe(User).ranked_for_ids(for_user, scoped_ids: public_user_ids)

    return scoped.order(target_attr) if ranked_ids.empty?

    field_clause = "FIELD(sponsorships.#{target_attr}, #{ranked_ids.join(", ")})"
    scoped.order(Arel.sql("IF(#{field_clause} = 0, 1, 0), #{field_clause}"))
      .order(target_attr)
  }

  scope :ranked_for_public_profile, -> do
    order(active: :desc).order(privacy_level: :asc)
  end

  scope :join_sponsors_listings_on_sponsorable, -> do
    joins("INNER JOIN sponsors_listings ON " \
      "sponsors_listings.sponsorable_id = sponsorships.sponsorable_id")
  end

  scope :for_listing, ->(listing) do
    join_sponsors_listings_on_sponsorable.where(sponsors_listings: { id: listing })
  end

  # Public: Get all sponsorships that match the given tier price under the tier's listing.
  scope :at_sponsors_tier_price, ->(tier) do
    joins(:tier).where(sponsors_tiers: {
      sponsors_listing_id: tier.sponsors_listing_id,
      monthly_price_in_cents: tier.monthly_price_in_cents,
    })
  end

  # Public: Get sponsorships where the specified user or organization is the sponsor.
  scope :from_sponsor, ->(user_or_org) { where(sponsor_id: user_or_org) }

  # Public: Get sponsorships where the specified user or organization is the recipient of the
  # sponsorship (the one being sponsored).
  scope :with_user_or_org_sponsorable, ->(user_or_org) do
    where(sponsorable_id: user_or_org)
  end

  # Public: Get sponsorships where the sponsor can be known to the given viewer. That is, private
  # sponsorships will only be included when it's the viewer being sponsored or doing the
  # sponsoring, or when an org that the viewer belongs to or billing manages is being sponsored or
  # doing the sponsoring.
  #
  # viewer - the User who's signed in; nil for an anonymous viewer
  # linked_org_sponsor_ids_by_org_id - optional Hash of Organization IDs to their linked Organization ID, if known
  scope :sponsor_visible_to, ->(viewer, linked_org_sponsor_ids_by_org_id: {}) do
    if viewer
      # Users can always see the sponsor identity when they're the one making or receiving the sponsorship,
      # or when the sponsorship is public:
      sponsorships = privacy_public
        .or(scoped.from_sponsor(viewer))
        .or(scoped.with_user_or_org_sponsorable(viewer))

      viewer_member_org_ids = viewer.organization_ids_by_member_or_billing_manager_status[:member]
      if viewer_member_org_ids.any?
        # Users can see the identity of private sponsors when they're a member of the organization being sponsored:
        sponsorships = sponsorships.or(scoped.with_user_or_org_sponsorable(viewer_member_org_ids))
      end

      viewer_member_or_bill_mgr_org_ids = viewer_member_org_ids |
        viewer.organization_ids_by_member_or_billing_manager_status[:billing_manager]
      if viewer_member_or_bill_mgr_org_ids.any?
        # Users can see the identity of private sponsors when they're a member or billing manager of the sponsoring
        # organization:
        sponsorships = sponsorships.or(scoped.from_sponsor(viewer_member_or_bill_mgr_org_ids))

        linked_org_sponsor_ids = if viewer_member_or_bill_mgr_org_ids.all? { |id| linked_org_sponsor_ids_by_org_id.key?(id) }
          linked_org_sponsor_ids_by_org_id.slice(*viewer_member_or_bill_mgr_org_ids).values.flatten.uniq
        else
          viewer.member_or_billing_manager_linked_organization_sponsor_ids
        end
        sponsorships = sponsorships.or(scoped.from_sponsor(linked_org_sponsor_ids)) if linked_org_sponsor_ids.any?
      end

      sponsorships
    else
      # Anonymous users can only see sponsors who are sponsoring publicly:
      privacy_public
    end
  end

  # Public: Get sponsorships where the cost of the chosen tier is something the given user is
  # allowed to know. That is, the given user is either the one sponsoring or the one being
  # sponsored.
  #
  # viewer - the User who's signed in; nil for an anonymous viewer
  scope :amount_visible_to, ->(viewer) do
    if viewer
      sponsorships = scoped.from_sponsor(viewer).or(scoped.with_user_or_org_sponsorable(viewer))

      # Org admins and billing managers can know how much $ their org is paying:
      viewer_sponsor_org_ids = viewer.potential_organization_sponsor_ids
      if viewer_sponsor_org_ids.any?
        linked_viewer_org_ids = OrganizationProfile.for_organization(viewer_sponsor_org_ids)
          .pluck(:sponsoring_linked_organization_id)
        sponsorships = sponsorships.or(scoped.from_sponsor(viewer_sponsor_org_ids | linked_viewer_org_ids))
      end

      # Org admins can know how much $ their org is receiving from a sponsor:
      viewer_admined_org_ids = viewer.owned_organization_ids
      if viewer_admined_org_ids.any?
        sponsorships = sponsorships.or(scoped.with_user_or_org_sponsorable(viewer_admined_org_ids))
      end

      sponsorships
    else
      none
    end
  end

  # Public: Preload the associations to resolve "linked_or_direct_sponsor" which represents
  # the user/org who should be credited with the sponsorship (and may be different than the
  # user/org who paid for the sponsorship).
  scope :with_linked_org_preloads, -> do
    includes(sponsor: { sponsoring_parent_organization_profile: :organization })
  end

  scope :newest_first, -> { order(created_at: :desc) }

  belongs_to :sponsor, class_name: "User", required: true, inverse_of: :sponsorships_as_sponsor
  belongs_to :sponsorable, class_name: "User", required: true,
    inverse_of: :sponsorships_as_sponsorable
  belongs_to :tier, class_name: "SponsorsTier", required: true, autosave: true,
    inverse_of: :sponsorships, foreign_key: :subscribable_id
  belongs_to :subscription_item, class_name: "Billing::SubscriptionItem"
  belongs_to :invoiced_sponsorship_transfer, autosave: true
  belongs_to :sponsors_listing, foreign_key: :sponsorable_id, primary_key: :sponsorable_id,
  inverse_of: :sponsorships

  has_one :plan_subscription, through: :subscription_item, class_name: "Billing::PlanSubscription"
  has_one :latest_one_time_payment_activity, ->(sponsorship) {
    T.bind(self, T.untyped)
    unscope(where: :sponsorship_id).for_sponsorable_and_sponsor(sponsorship.sponsorable_id, sponsorship.sponsor_id)
      .is_new_sponsorship.one_time.by_timestamp
  }, class_name: "SponsorsActivity"
  has_one :sponsors_listing_stafftools_metadata, through: :sponsors_listing, source: :stafftools_metadata
  has_one :sponsorship_repository, ->(sponsorship) {
    T.bind(self, T.untyped)
    unscope(where: :sponsorship_repository_id).for_tier(sponsorship.subscribable_id).for_sponsor(sponsorship.sponsor_id)
      .for_sponsorable(sponsorship.sponsorable_id)
  }, inverse_of: :sponsorship

  before_validation :sanitize_sponsorable_metadata, on: [:create, :update]

  validates :subscription_item, presence: true, unless: -> do
    T.bind(self, Sponsorship)
    manual_invoiced? || patreon?
  end
  validates :expires_at, presence: true, if: :manual_invoiced_or_one_time?
  validates :subscribable_selected_at, presence: true, on: :create
  validates :sponsor_id, uniqueness: { scope: :sponsorable_id }
  validates_presence_of :privacy_level
  validates :maintainer_notes, unicode3: true

  validate :ensure_sponsorable_or_sponsor_are_not_blocked, on: :create
  validate :sponsors_listing_must_be_approved, if: :active?
  validate :tier_and_sponsorable_agree
  validate :custom_or_invoiced_tier_not_already_used
  validate :no_changes_while_locked, on: :update, if: :was_locked?
  validate :manual_invoiced_tier_has_no_subscription_item, if: :manual_invoiced?
  validate :no_self_sponsorship

  delegate :repository_id, to: :tier

  # Public: Get IDs of the users and organizations who should be credited as the sponsors in the given sponsorships.
  #
  # sponsorships - an ActiveRecord::Relation of Sponsorship
  sig { params(sponsorships: ActiveRecord::Relation).returns(T::Array[Integer]) }
  def self.sponsor_ids_from(sponsorships)
    sponsor_ids = sponsorships.pluck(:sponsor_id)
    linked_org_ids_by_sponsor_id = OrganizationProfile.for_sponsoring_linked_org(sponsor_ids)
      .pluck(:sponsoring_linked_organization_id, :organization_id)
      .to_h
    sponsor_ids.map do |sponsor_id|
      linked_org_ids_by_sponsor_id[sponsor_id] || sponsor_id
    end
  end

  # Public: Reject sponsorships that are blocked for the current user
  sig do
    params(
      sponsorships: T.any(T::Array[Sponsorship], ActiveRecord::Relation),
      current_user: T.nilable(User)
    ).returns(T::Array[Sponsorship])
  end
  def self.reject_blocked_sponsorships(sponsorships, current_user:)
    # If this method uses `reject` it will create an Array of records, and that new Array will not be paginated.
    # So instead we need to use `to_a` on the ActiveRecord relation, store it in a local var, mutate it in place
    # with `reject!`, and then return it so that the pagination (page, total_entries, etc.) is maintained.
    sponsorships = sponsorships.to_a

    GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :blocked_for?, current_user)

    sponsorships.reject! do |sponsorship|
      sponsorship.blocked_for?(current_user)
    end

    sponsorships
  end

  # Public: Get paired lists of sponsor IDs and tier IDs for which billing transactions
  # and line items exist, indicating that the sponsor made a sponsorship at that tier.
  #
  # sponsor_ids_to_check - Array of Integer User or Organization IDs to check for potential
  #                        sponsors
  # tier_ids_to_check - Array of Integer SponsorsTier IDs to check to see if any of the sponsors
  #                     created sponsorships with these tiers
  #
  # Returns an Array of Arrays, with each inner Array having two values: a sponsor ID and a tier ID
  # that are represented in a billing transaction and line item. Returns unique sponsor+tier combos,
  # even if there are many line items for a combination.
  sig do
    params(
      sponsor_ids_to_check: T::Array[Integer],
      tier_ids_to_check: T::Array[Integer]
    ).returns(T::Array[[Integer, Integer]])
  end
  def self.sponsor_and_tier_ids_with_line_items(sponsor_ids_to_check, tier_ids_to_check)
    ::Billing::BillingTransaction::LineItem
      .joins(:billing_transaction)
      .sponsorships
      .where(subscribable_id: tier_ids_to_check)
      .merge(::Billing::BillingTransaction.for_user(sponsor_ids_to_check))
      .distinct
      .pluck("billing_transactions.user_id", :subscribable_id)
  end

  # Public: Calculate the recurring monthly price in US cents for a given scope or list of
  # sponsorships. Only includes sponsorships that use a recurring tier. Will only sum the cost of
  # sponsorships that the given viewer is allowed to know the price of.
  #
  # scope_or_list - ActiveRecord::Relation or Array of Sponsorship records
  # viewer - the currently authenticated User
  # include_invoiced - Boolean indication whether to include non-Zuora invoiced sponsorships in the calculation
  sig do
    params(
      scope_or_list: T.any(ActiveRecord::Relation, T::Array[Sponsorship]),
      viewer: T.nilable(User),
      include_invoiced: T::Boolean
    ).returns(Integer)
  end
  def self.total_recurring_monthly_price_in_cents(scope_or_list, viewer:, include_invoiced: false)
    async_total_recurring_monthly_price_in_cents(scope_or_list,
      viewer: viewer,
      include_invoiced: include_invoiced
    ).sync
  end

  sig do
    params(
      scope_or_list: T.any(ActiveRecord::Relation, T::Array[Sponsorship]),
      viewer: T.nilable(User),
      include_invoiced: T::Boolean
    ).returns(Promise[Integer])
  end
  def self.async_total_recurring_monthly_price_in_cents(scope_or_list, viewer:, include_invoiced: false)
    if scope_or_list.is_a?(ActiveRecord::Relation)
      relation = if include_invoiced
        T.unsafe(scope_or_list).recurring.or(scope_or_list.joins(:tier).invoiced)
      else
        T.unsafe(scope_or_list).recurring
      end
      total_cents = relation
        .amount_visible_to(viewer)
        .sum("sponsors_tiers.monthly_price_in_cents")
      Promise.resolve(total_cents)
    else
      promises = scope_or_list.map do |sponsorship|
        sponsorship.async_recurring_monthly_price_in_cents_for(viewer, include_invoiced: include_invoiced)
      end
      Promise.all(promises).then { |cents_list| cents_list.sum }
    end
  end

  # Public: Calculate the recurring monthly price in US dollars for a given scope or list of
  # sponsorships. Only includes sponsorships that use a recurring tier. Will only sum the cost of
  # sponsorships that the given viewer is allowed to know the price of.
  #
  # scope_or_list - ActiveRecord::Relation or Array of Sponsorship records
  # viewer - the currently authenticated User
  #
  # Returns an Integer since Sponsors tiers use whole-dollar amounts only.
  sig do
    params(
      scope_or_list: T.any(ActiveRecord::Relation, T::Array[Sponsorship]),
      viewer: T.nilable(User)
    ).returns(Integer)
  end
  def self.total_recurring_monthly_price_in_dollars(scope_or_list, viewer:)
    async_total_recurring_monthly_price_in_dollars(scope_or_list, viewer: viewer).sync
  end

  sig do
    params(
      scope_or_list: T.any(ActiveRecord::Relation, T::Array[Sponsorship]),
      viewer: T.nilable(User)
    ).returns(Promise[Integer])
  end
  def self.async_total_recurring_monthly_price_in_dollars(scope_or_list, viewer:)
    async_total_recurring_monthly_price_in_cents(scope_or_list,
      viewer: viewer,
    ).then { |total_cents| total_cents / 100 }
  end

  # Public: Check whether or not the specified user/org is sponsoring each of the given
  # users/orgs.
  #
  # sponsorable_ids - list of user/org IDs that may or may not have public Sponsors listings
  # sponsor_id - user/org ID to check
  # viewer - the currently authenticated User
  #
  # Returns a Hash of integer User/Organization IDs => Boolean for whether the given
  # sponsor_id is sponsoring each user/org.
  sig do
    params(
      sponsorable_ids: T::Enumerable[Integer],
      sponsor_id: T.any(User, Integer, Organization, String),
      viewer: T.nilable(User)
    ).returns(T::Hash[Integer, T::Boolean])
  end
  def self.sponsor_status_by_sponsorable_id(sponsorable_ids:, sponsor_id:, viewer: nil)
    sponsorships = active.where(sponsorable_id: sponsorable_ids, sponsor_id: sponsor_id)
      .sponsor_visible_to(viewer)

    sponsored_sponsorable_ids = Set.new(sponsorships.pluck(:sponsorable_id))
    sponsorable_ids.map { |id| [id, sponsored_sponsorable_ids.include?(id)] }.to_h
  end

  # Public: Get a mapping of which users and organizations are sponsoring a given maintainer.
  #
  # sponsor_or_ids - Array of Users/Orgs or Integer IDs to check for sponsorship
  # sponsorable_id - Integer ID of the User/Org maintainer
  # viewer - the User/Org viewing the results, or nil for an anonymous viewer
  #
  # If no viewer is passed, only public sponsorships will be checked, otherwise
  # the viewer's identity determines which sponsorships will be returned.
  # For example, I can see all private sponsorships I fund, and a maintainer can see
  # my private sponsorship of them but not my other private sponsorships.
  #
  # Returns a Hash of Integer id => Boolean representing whether the viewer
  # can see that the passed User/Org has a sponsorship for the passed maintainer.
  sig do
    params(
      sponsors_or_ids: T::Array[T.any(User, Integer, Organization, String)],
      sponsorable_id: T.any(User, Integer, Organization, String),
      viewer: T.nilable(User)
    ).returns(T::Hash[Integer, T::Boolean])
  end
  def self.sponsor_status_by_sponsor_id(sponsors_or_ids, sponsorable_id:, viewer: nil)
    sponsorships = Sponsorship.active.sponsor_visible_to(viewer).from_sponsor(sponsors_or_ids)
      .with_user_or_org_sponsorable(sponsorable_id)
    sponsor_ids = sponsorships.pluck(:sponsor_id)
    sponsor_ids.each_with_object(Hash.new(false)) do |sponsor_id, result|
      result[sponsor_id] = true
    end
  end

  # Public: Calculate the expiration date for a one-time or invoiced sponsorship that is being
  # activated today.
  sig { returns ActiveSupport::TimeWithZone }
  def self.expiration_time
    DAYS_TO_SHOW_ONE_TIME_SPONSORS.days.from_now.end_of_day
  end

  # Public: Get sponsor counts for many listings at once.
  #
  # listing_ids - an Array of SponsorsListing IDs
  # viewer - the currently authenticated User or nil
  #
  # Returns a Hash[Integer] => Integer where the keys are listing IDs and the
  # values are how many active sponsors each listing has.
  sig { params(listing_ids: T::Array[Integer], viewer: T.nilable(User)).returns(T::Hash[Integer, Integer]) }
  def self.sponsor_counts_by_listing_id(listing_ids, viewer:)
    Hash.new(0).merge(
      active
        .for_listing(listing_ids)
        # Include `filter_spam_for` as the last scope since it will run queries itself on the already-scoped
        # query, so we want that set of sponsorships to be as small as possible:
        .filter_spam_for(viewer)
        .select("COUNT(sponsorships.id) AS count, sponsors_listings.id AS listing_id")
        .group("listing_id")
        .map { |sponsorship| [T.unsafe(sponsorship).listing_id, T.unsafe(sponsorship).count] }
        .to_h
    )
  end

  # Public: Get how many sponsors the specified listing has.
  #
  # listing_id - SponsorsListing ID, integer
  sig { params(listing_id: Integer).returns(Integer) }
  def self.sponsors_count_for(listing_id)
    active.for_listing(listing_id).count
  end

  # Public: Check if the given tier represents a plan change for this sponsorship or not.
  #
  # Returns true when the given tier is the same as what this sponsorship already has.
  sig { params(new_tier: T.nilable(SponsorsTier)).returns(T::Boolean) }
  def equal_tier?(new_tier)
    return false unless new_tier.is_a?(SponsorsTier)
    return true if new_tier.id == subscribable_id
    return true if new_tier.equal_custom_tier?(tier)
    false
  end

  # Public: Check if this sponsorship is currently using a tier with the same cost as the given tier.
  sig { params(other_tier: T.any(SponsorsTier, SponsorsPatreonTier)).returns(T::Boolean) }
  def equally_priced_tier?(other_tier)
    return false unless tier
    T.must(tier).equal_price?(other_tier)
  end

  sig { returns T.nilable(T.any(User, Organization, Business)) }
  def target_for_conditional_access
    sponsor&.target_for_conditional_access
  end

  # Public: Retrieve the repository the sponsor was granted access to as a result of this sponsorship, if any.
  sig { returns T.nilable(Repository) }
  def sponsors_only_repository
    tier&.repository_for_sponsor(sponsor)
  end

  # Public: Line items representing payment for this sponsorship. Includes line items from past
  # tiers this sponsorship has used as well as those for the current tier.
  #
  # Returns an ActiveRecord::Relation of Billing::BillingTransaction::LineItem.
  sig { returns ActiveRecord::Relation }
  def billing_transaction_line_items
    subscribable_ids = SponsorsTier.for_sponsorable(sponsorable_id).select(:id).distinct.pluck(:id)
    Billing::BillingTransaction::LineItem.sponsorships
      .for_subscribable_and_user(subscribable_ids, sponsor_id)
  end

  # Public: Get transaction IDs for any billing transaction associated with this sponsorship.
  sig { returns T::Array[String] }
  def billing_transaction_ids
    billing_transaction_line_items.select("billing_transactions.transaction_id").distinct.pluck(:transaction_id)
  end

  sig { returns Promise[T.any(User, Organization)] }
  def async_linked_or_direct_sponsor
    async_sponsor.then do |sponsor|
      next User.ghost unless sponsor
      next sponsor if sponsor&.user?
      sponsor.async_sponsoring_parent_organization.then do |parent_org|
        parent_org || sponsor
      end
    end
  end

  sig { returns T.any(User, Organization) }
  def linked_or_direct_sponsor
    async_linked_or_direct_sponsor.sync
  end

  sig { returns T.nilable(String) }
  def sponsorable_login
    sponsorable&.display_login
  end

  sig { returns T.nilable(String) }
  def sponsor_login
    sponsor&.display_login
  end

  sig { returns(T.nilable(String)) }
  def opposite_privacy_level
    if privacy_public?
      "private"
    elsif privacy_private?
      "public"
    end
  end

  # Public: Cancel a delayed sponsorship before it's applied
  sig { returns T::Boolean }
  def cancel_pending_activation
    change = pending_change
    return false unless change.present? && change.type == Sponsorship::PendingChange::Type::Activation
    deactivate_and_expire_without_callbacks
  end

  # Public: Cancel the current sponsorship.
  #
  # actor - the User who initiated this cancellation
  # force - Boolean capturing the urgency behind this cancellation. If true, subscription item-backed sponsorships
  #   will be cancelled immediately versus scheduling it for the sponsor's next billing date. For non-subscription
  #   item-backed sponsorships, e.g. Patreon and old-style invoiced, the sponsorship is always cancelled immediately
  #         a cancellation for the next billing date; not applicable for invoiced sponsorships
  # reason - Symbol from Sponsorship::InstrumentationDependency::HYDRO_CANCELLATION_REASONS representing why the sponsorship is being cancelled
  sig { params(actor: T.nilable(User), reason: T.nilable(Symbol), force: T::Boolean).returns(Billing::Public::ResultStruct) }
  def cancel(actor:, reason: nil, force: false)
    self.actor = actor
    subscription_item = self.subscription_item
    instrument_cancel_request(reason: reason, force: force, actor: actor)

    if manual_invoiced? || one_time_payment? || patreon? # sponsorship that can be active without an active sub item
      old_expires_at = expires_at
      success = deactivate_and_expire_without_callbacks

      if success && subscription_item
        success = deactivate_subscription_item_or_restore_sponsorship_activeness(old_expires_at)
      end

      instrument_cancellation
      after_deactivation if success

      Billing::Public::ResultStruct.new(success: !!success)
    elsif subscription_item
      begin
        subscription_item.cancel!(actor: actor, force: force).result
      rescue Billing::SubscriptionItem::MissingPlanSubscription => err
        Failbot.report(err)

        unless subscription_item.update(quantity: 0)
          return Billing::Public::ResultStruct.new(success: false, errors: subscription_item.errors.full_messages)
        end

        instrument_cancel(actor: actor)
        update_subscription_item(subscription_item)
        Billing::Public::ResultStruct.new(success: true)
      end
    else
      Billing::Public::ResultStruct.new(success: false, errors: ["No subscription item to cancel"])
    end
  end

  # Public: The formatted date the sponsorship was created.
  sig { returns T.nilable(String) }
  def sponsorship_created_at
    created_at&.strftime("%B %Y")
  end

  sig { void }
  def ensure_sponsorable_or_sponsor_are_not_blocked
    return if sponsorable.blank? || sponsor.blank?

    errors.add :sponsor, "is blocked" if T.must(sponsor).blocked_by?(sponsorable)
    errors.add :sponsorable, "is blocked" if T.must(sponsorable).blocked_by?(sponsor)
  end

  sig { void }
  def sponsors_listing_must_be_approved
    return unless sponsors_listing
    return if T.must(sponsors_listing).approved?

    errors.add :base, "Sponsors profile must be approved"
  end

  sig { void }
  def custom_or_invoiced_tier_not_already_used
    return unless tier
    return unless T.must(tier).custom? || T.must(tier).invoiced?

    other_sponsorships = T.must(tier).sponsorships
    other_sponsorships = other_sponsorships.where.not(id: id) if persisted?

    if other_sponsorships.any?
      errors.add(:tier, "has already been used for a sponsorship")
    end
  end

  sig { void }
  def manual_invoiced_tier_has_no_subscription_item
    return unless manual_invoiced?
    return unless subscription_item_id

    errors.add(:subscription_item, "cannot be associated with an invoiced sponsorship")
  end

  sig { void }
  def no_self_sponsorship
    return unless sponsor_id == sponsorable_id

    errors.add(:sponsor, "cannot sponsor themselves")
  end

  sig { void }
  def no_changes_while_locked
    return if recurring_payment?

    changed_locked_fields = changed - CHANGEABLE_FIELDS_WHILE_LOCKED
    changed_locked_fields.each do |field|
      errors.add(field, "cannot be changed when sponsorship is locked")
    end
  end

  sig { returns Symbol }
  def event_prefix() :sponsorship end

  sig { returns T::Hash[Symbol, T.untyped] }
  def event_payload
    payload = {
      :sponsor => sponsor,
      event_prefix => self,
      :active => active?,
      :public => privacy_public?,
      :payment_source => payment_source,
    }
    if tier
      payload[:frequency] = T.must(tier).frequency
      payload[:current_tier_id] = subscribable_id
      payload[:current_tier_monthly_amount_in_cents] = T.must(tier).monthly_price_in_cents
    end

    # Merging the event context will make sure that the audit log will show up
    # for the sponsoring org, when the sponsor is an org and not a user.
    #
    # For example, if Jane is sponsoring someone on behalf of Rich Co., then
    # Rich Co. will be the sponsor and the `event_context` will include the
    # `org` and `org_id` for Rich Co. on the event payload. That way the audit
    # log event will show up in the audit log for Jane because she is the actor
    # AND it will show up in Rich Co's audit log because the `org/org_id` is
    # set.
    payload.merge!(T.must(sponsor).event_context) if sponsor

    # This is used to display who received sponsorship
    payload.merge(
      sponsorable_event_key => sponsorable_login,
      "#{sponsorable_event_key}_id".to_sym => sponsorable_id,
    )
  end

  sig { returns Symbol }
  def sponsorable_event_key
    if sponsorable.is_a?(Organization)
      :sponsorable_org
    else
      :sponsorable_user
    end
  end

  sig { returns T.nilable(T::Boolean) }
  def matchable?
    sponsors_listing&.matchable? && sponsor&.eligible_for_sponsorship_match?(sponsorable: sponsorable)
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_amount_readable_by?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer

    async_sponsor.then do |sponsor|
      sponsor.async_sponsorship_amounts_as_sponsor_readable_by?(viewer).then do |is_readable_via_sponsor|
        next true if is_readable_via_sponsor

        async_sponsorable.then do |sponsorable|
          sponsorable.async_sponsorship_amounts_as_sponsorable_readable_by?(viewer)
        end
      end
    end
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_sponsor_readable_by?(viewer)
    return Promise.resolve(T.let(true, T::Boolean)) if privacy_public?
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer

    sponsor_check_promise = async_linked_or_direct_sponsor_billing_manageable_by?(viewer)
    sponsor_check_promise.then do |is_readable_via_sponsor|
      next true if is_readable_via_sponsor

      async_sponsorable.then do |sponsorable|
        next true if viewer == sponsorable
        next true if to_organization? && sponsorable.member?(viewer)

        sponsorable.async_sponsors_listing.then do |listing|
          listing.async_adminable_by?(viewer)
        end
      end
    end
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_linked_or_direct_sponsor_billing_manageable_by?(viewer)
    async_sponsor.then do |sponsor|
      next false unless sponsor
      next viewer == sponsor if sponsor.user?

      sponsor.async_billing_manageable_by?(viewer).then do |can_viewer_manage_billing_for_sponsor|
        next true if can_viewer_manage_billing_for_sponsor

        sponsor.async_sponsoring_parent_organization.then do |parent_org|
          next false unless parent_org

          parent_org.async_billing_manageable_by?(viewer)
        end
      end
    end
  end

  # Public - Should we be hiding this sponsorship from this viewing user?
  # If the sponsor or the maintainer being sponsored is spammy, and the user
  # trying to view us is not the spammer themselves, nor is the viewer a staff member,
  # then run and hide.
  sig { params(viewer: T.nilable(User)).returns(Promise[T.nilable(T::Boolean)]) }
  def async_hide_from_user?(viewer)
    async_sponsor.then do |sponsor|
      next true if sponsor&.hide_from_user?(viewer)

      async_sponsorable.then do |sponsorable|
        sponsorable&.hide_from_user?(viewer)
      end
    end
  end

  # Public: Checks if the given user can see the identity of the sponsor
  # in this sponsorship.
  #
  # viewer - the User wanting to learn the identity of the sponsor
  #
  #
  # Examples
  #
  #   # To prevent N+1s when this method is called on a list of Sponsorship records, prefill it this way:
  #
  #   # Execute 1 query to preload (usually in a controller action):
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :sponsor_readable_by?, current_user)
  #
  #   sponsorships.each do |sponsorship|
  #     # Method is preloaded and memoized -- no queries are executed here!
  #     sponsorship.sponsor_readable_by?(current_user)
  #   end
  #
  # Returns a Boolean.
  batch_method :sponsor_readable_by? do |sponsorships, viewer|
    promises = sponsorships.map { |s| s.async_sponsor_readable_by?(viewer) }
    results = Promise.all(promises).sync
    sponsorships.zip(results).to_h
  end

  # Public: low-level access to changes via Billing::PendingSubscriptionItemChange
  batch_method :pending_subscription_item_change do |sponsorships|
    next if sponsorships.empty?

    change_promises = sponsorships.map do |sponsorship|
      sponsorship.async_subscription_item.then do |subscription_item|
        next unless subscription_item.present?
        subscription_item.async_pending_subscription_item_change
      end
    end
    changes = Promise.all(change_promises).sync

    sponsorships.zip(changes).to_h
  end

  # Public: high-level access to changes via Sponsorship::PendingChange
  batch_method :pending_change do |sponsorships|
    next if sponsorships.empty?

    GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :pending_subscription_item_change)
    sub_items = sponsorships.map(&:subscription_item)
    pending_sub_item_changes = sponsorships.map(&:pending_subscription_item_change)

    GitHub::PrefillAssociations.prefill_associations(sub_items + pending_sub_item_changes, :subscribable)

    changes = sponsorships.map do |sponsorship|
      sub_item = sponsorship.subscription_item
      change = sponsorship.pending_subscription_item_change
      next unless change.present?

      PendingChange.new(
        current_subscription_item: sub_item,
        pending_subscription_item_change: change,
      )
    end

    sponsorships.zip(changes).to_h
  end

  # Public: Was this sponsorship made along with at least one other, using our Bulk Sponsorship tool?
  #
  # Examples
  #
  #   # To prevent N+1s when this method is called on a list of Sponsorship records, prefill it this way:
  #
  #   # Execute 1 query to preload (usually in a controller action):
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :via_bulk_sponsorship?)
  #
  #   sponsorships.each do |sponsorship|
  #     # Method is preloaded and memoized -- no queries are executed here!
  #     sponsorship.via_bulk_sponsorship?
  #   end
  #
  # Returns a Boolean.
  batch_method :via_bulk_sponsorship? do |sponsorships|
    if sponsorships.empty?
      {}
    else
      base_query = SponsorsActivity.is_new_sponsorship.select(:sponsorable_id, :sponsor_id, :via_bulk_sponsorship)
      sponsorship = sponsorships.first
      activities = base_query.for_sponsorable_and_sponsor(sponsorship.sponsorable_id, sponsorship.sponsor_id)
        .with_sponsors_tier(sponsorship.subscribable_id)

      sponsorships.drop(1).each do |sponsorship|
        activities = activities.or(
          base_query.for_sponsorable_and_sponsor(sponsorship.sponsorable_id, sponsorship.sponsor_id)
            .with_sponsors_tier(sponsorship.subscribable_id)
        )
      end

      # Do a nested SELECT so we can only fetch the most recent 'new_sponsorship' activity for each
      # tier+sponsor+sponsorable combination, to reduce how much data is loaded when a sponsor has made many payments
      # using the same tier for the same maintainer over time:
      outer_activities = SponsorsActivity.arel_table
      sa = SponsorsActivity.arel_table.alias("sa")
      timestamp_of_latest_activity = outer_activities
        .project(sa[:timestamp].maximum).from(sa)
        .where(
          outer_activities[:sponsors_tier_id].eq(sa[:sponsors_tier_id])
            .and(outer_activities[:sponsor_id].eq(sa[:sponsor_id]))
            .and(outer_activities[:sponsorable_id].eq(sa[:sponsorable_id]))
            .and(outer_activities[:action].eq(sa[:action]))
        )
      activities = activities.where(outer_activities[:timestamp].in(timestamp_of_latest_activity))

      # Sample SQL for the query that will be run here:
      #
      #  SELECT `sponsors_activities`.`sponsorable_id`, `sponsors_activities`.`sponsor_id`,
      #    `sponsors_activities`.`via_bulk_sponsorship`
      #  FROM `sponsors_activities`
      #  WHERE `sponsors_activities`.`action` = 0
      #  AND (
      #    `sponsors_activities`.`sponsorable_id` = 19
      #      AND `sponsors_activities`.`sponsor_id` = 23
      #      AND `sponsors_activities`.`sponsors_tier_id` = 7
      #    OR `sponsors_activities`.`sponsorable_id` = 35
      #      AND `sponsors_activities`.`sponsor_id` = 34
      #      AND `sponsors_activities`.`sponsors_tier_id` = 13
      #    OR `sponsors_activities`.`sponsorable_id` = 38
      #      AND `sponsors_activities`.`sponsor_id` = 37
      #      AND `sponsors_activities`.`sponsors_tier_id` = 14
      #  )
      #  AND `sponsors_activities`.`timestamp` IN (
      #    SELECT MAX(`sa`.`timestamp`)
      #    FROM `sponsors_activities` `sa`
      #    WHERE `sponsors_activities`.`sponsors_tier_id` = `sa`.`sponsors_tier_id`
      #    AND `sponsors_activities`.`sponsor_id` = `sa`.`sponsor_id`
      #    AND `sponsors_activities`.`sponsorable_id` = `sa`.`sponsorable_id`
      #    AND `sponsors_activities`.`action` = `sa`.`action`
      #  )
      activities = activities.to_a

      activities_by_sponsorable_and_sponsor = activities.each_with_object({}) do |activity, hash|
        sponsorable_id = activity.sponsorable_id
        sponsor_id = activity.sponsor_id
        hash[sponsorable_id] ||= {}
        hash[sponsorable_id][sponsor_id] = activity
      end

      sponsorships.each_with_object({}) do |sponsorship, hash|
        activities_for_sponsorable = activities_by_sponsorable_and_sponsor[sponsorship.sponsorable_id] || {}
        activity = activities_for_sponsorable[sponsorship.sponsor_id]
        hash[sponsorship] = if activity
          activity.via_bulk_sponsorship
        else
          false
        end
      end
    end
  end

  # Examples
  #
  #   # To prevent N+1s when this method is called on a list of Sponsorship records, prefill it this way:
  #
  #   # Execute 1 query to preload (usually in a controller action):
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :latest_billing_transaction_line_item_for_tier)
  #
  #   sponsorships.each do |sponsorship|
  #     # Method is preloaded and memoized -- no queries are executed here!
  #     sponsorship.latest_billing_transaction_line_item_for_tier
  #   end
  #
  # Returns a Billing::BillingTransaction::LineItem or nil.
  batch_method :latest_billing_transaction_line_item_for_tier do |sponsorships|
    if sponsorships.any?
      sponsorships_by_tier_and_sponsor_id = sponsorships.each_with_object({}) do |sponsorship, hash|
        tier_id = sponsorship.subscribable_id
        sponsor_id = sponsorship.sponsor_id
        hash[tier_id] ||= {}
        hash[tier_id][sponsor_id] = sponsorship
      end
      base_query = Billing::BillingTransaction::LineItem.sponsorships.joins(:billing_transaction)

      tier_id = sponsorships.first.subscribable_id
      sponsor_id = sponsorships.first.sponsor_id
      line_items = base_query.for_subscribable_and_user(tier_id, sponsor_id)

      sponsorships.drop(1).each do |sponsorship|
        tier_id = sponsorship.subscribable_id
        sponsor_id = sponsorship.sponsor_id
        line_items = line_items.or(base_query.for_subscribable_and_user(tier_id, sponsor_id))
      end

      outer_line_items = Billing::BillingTransaction::LineItem.arel_table
      outer_billing_transactions = Billing::BillingTransaction.arel_table
      li = Billing::BillingTransaction::LineItem.arel_table.alias("li")
      bt = Billing::BillingTransaction.arel_table.alias("bt")
      id_of_latest_line_item = outer_line_items
        .project(li[:id].maximum).from(li)
        .join(bt).on(li[:billing_transaction_id].eq(bt[:id]))
        .where(
          outer_line_items[:subscribable_type].eq(li[:subscribable_type])
          .and(outer_billing_transactions[:user_id].eq(bt[:user_id]))
          .and(outer_line_items[:subscribable_id].eq(li[:subscribable_id]))
        )
      line_items = line_items
        .where(outer_line_items[:id].in(id_of_latest_line_item))
        .includes(:billing_transaction)

      line_items.each_with_object({}) do |line_item, hash|
        tier_id = line_item.subscribable_id
        sponsor_id = line_item.billing_transaction&.user_id
        sponsorship = sponsorships_by_tier_and_sponsor_id[tier_id][sponsor_id]
        hash[sponsorship] = line_item
      end
    else
      {}
    end
  end

  # Public: Checks if sponsor uses Zuora credit balance from an invoice.
  #
  # Examples
  #
  #   # To prevent N+1s when this method is called on a list of Sponsorship records, # prefill it this way:
  #
  #   # Execute 1 query to preload (usually in a controller action):
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :sponsors_invoiced?)
  #
  #   sponsorships.each do |sponsorship|
  #     # Method is preloaded and memoized -- no queries are executed here!
  #     sponsorship.sponsors_invoiced?
  #   end
  #
  # Returns a Boolean.
  batch_method :sponsors_invoiced? do |sponsorships|
    user_ids = sponsorships.map(&:sponsor_id)
    users_by_id = User.where(id: user_ids).includes(:sponsors_customer).index_by(&:id)

    sponsorships.each_with_object({}) do |sponsorship, result|
      sponsor = users_by_id[sponsorship.sponsor_id]
      result[sponsorship] = sponsor ? sponsor.sponsors_invoiced? : false
    end
  end

  # Public: Checks if this sponsorship is considered blocked for the current user.
  #
  # If the current user is logged out, or is neither the sponsor nor the sponsorable, then we hide the sponsorship if
  # the sponsor or sponsorable are blocking the other.
  #
  # If the current user is the sponsor or sponsorable, we don't want to reveal to the them that they have been
  # blocked, so we only want to consider the sponsorship as blocked if the current user is the one doing the blocking.
  #
  # Context: https://github.com/github/github/pull/234788#discussion_r965226588
  #
  # Example:
  #
  #   # To prevent N+1s when this method is called on a list of Sponsorship records, prefill it this way:
  #
  #   # Usually in a controller action:
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :blocked_for?, current_user)
  #
  #   sponsorships.each do |sponsorship|
  #     # Method is preloaded and memoized -- no queries are executed here!
  #     sponsorship.blocked_for?(current_user)
  #   end
  #
  # Returns a Boolean.
  batch_method :blocked_for? do |sponsorships, current_user|
    GitHub::PrefillAssociations.prefill_associations(sponsorships, [:sponsor, :sponsorable])
    promises = sponsorships.map do |sponsorship|
      sponsorable = sponsorship.sponsorable
      sponsor = sponsorship.sponsor

      if sponsorable && current_user == sponsorable
        sponsorable.async_blocking?(sponsor)
      elsif sponsor && current_user == sponsor
        sponsor.async_blocking?(sponsorable)
      else # viewer is not part of the sponsorship, or is anonymous
        sponsor_blocking_check = sponsor ? sponsor.async_blocking?(sponsorable) : Promise.resolve(false)
        sponsorable_blocking_check = sponsorable ? sponsorable.async_blocking?(sponsor) : Promise.resolve(false)
        Promise.all([
          sponsor_blocking_check,
          sponsorable_blocking_check,
        ]).then do |is_sponsor_blocking_sponsorable, is_sponsorable_blocking_sponsor|
          is_sponsor_blocking_sponsorable || is_sponsorable_blocking_sponsor
        end
      end
    end
    results = Promise.all(promises).sync
    sponsorships.zip(results).to_h
  end

  # Public: Check if the given user can modify this sponsorship, such as changing its privacy level, or cancel it.
  #
  # viewer - the User wanting to modify the sponsorship
  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def adminable_by?(viewer)
    return false unless viewer.present?

    return true if viewer.id == sponsor_id

    return true if viewer.potential_sponsor_ids.include?(sponsor_id)

    return true if viewer.can_admin_sponsors_listings? && sponsor&.sponsors_invoiced?

    return false unless sponsor&.sponsoring_parent_organization.present?

    T.must(sponsor).sponsoring_parent_organization.billing_manageable_by?(viewer)
  end

  sig { returns T.nilable(T::Boolean) }
  def publicly_visible?
    active? && sponsors_listing&.approved?
  end

  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(viewer)
    return true if publicly_visible?
    return false unless viewer
    adminable_by?(viewer)
  end

  # Public: Checks if the given user can see the dollar amount of this sponsorship.
  #
  # viewer - the User wanting to view the dollar value of this sponsorship
  sig { params(viewer: T.nilable(User)).returns(T.nilable(T::Boolean)) }
  def amount_readable_by?(viewer)
    return false unless viewer
    return true if sponsor&.sponsorship_amounts_as_sponsor_readable_by?(viewer)
    sponsorable&.sponsorship_amounts_as_sponsorable_readable_by?(viewer)
  end

  sig do
    params(sponsorable: T.any(User, Organization), tier: T.nilable(SponsorsTier)).returns(ActiveRecord::Relation)
  end
  def self.all_active_as_sponsorable(sponsorable:, tier: nil)
    sponsorships = sponsorable.active_sponsorships_as_sponsorable
    if tier
      sponsorships = if tier.custom?
        sponsorships.at_sponsors_tier_price(tier)
      else
        sponsorships.with_tier(tier)
      end
    end

    sponsorships.newest_first
  end

  # Public: Get the highest priority sponsorship from a given list, where priority is measured
  # as premium > public > private.
  #
  # sponsorships - a Set of Sponsorship records
  # include_premium_sponsorships - Boolean indication whether should premium sponsorships be considered
  #
  # Returns a Sponsorship from the given list.
  sig do
    params(
      sponsorships: T::Set[Sponsorship],
      include_premium_sponsorships: T::Boolean
    ).returns(T.nilable(Sponsorship))
  end
  def self.highest_priority_sponsorship(sponsorships, include_premium_sponsorships: false)
    premium_sponsorship = if include_premium_sponsorships
      GitHub::PrefillAssociations.prefill_batch_method(sponsorships.to_a, :sponsors_invoiced?)
      sponsorships.detect(&:sponsors_invoiced?)
    end
    return premium_sponsorship if premium_sponsorship

    public_sponsorship = sponsorships.detect(&:privacy_public?)
    return public_sponsorship if public_sponsorship

    sponsorships.first
  end

  sig { params(sponsorable: T.any(User, Organization)).returns(T::Boolean) }
  def first_for?(sponsorable:)
    # If the sponsorship was previously inactive and is now active, this isn't
    # considered the first sponsorship anymore. This is an unfortunate side effect of
    # sponsorships being mutable
    return false if was_activated?

    self == Sponsorship.first_for(sponsorable: sponsorable)
  end

  sig { params(sponsorable: T.any(User, Organization)).returns(T.nilable(Sponsorship)) }
  def self.first_for(sponsorable:)
    Sponsorship.where(sponsorable: sponsorable)
      .order("created_at ASC")
      .first
  end

  sig { returns T::Boolean }
  def has_pending_cancellation?
    return false unless pending_subscription_item_change.present?
    pending_subscription_item_change.cancellation?
  end

  sig { returns T::Boolean }
  def has_pending_activation?
    return false unless pending_change.present?
    pending_change.activation?
  end

  sig { params(prefix: Symbol).returns(T::Hash[Symbol, T.nilable(Integer)]) }
  def event_context(prefix: event_prefix)
    { "#{prefix}_id".to_sym => id }
  end

  # Public: Whether this sponsorship is unpaid yet still active, and is in a state such that it's safe to retry
  # collecting payment for it.
  sig { returns T::Boolean }
  def can_retry_collecting_payment?
    return false if paid? # nothing to retry, we're good
    return false unless active? && one_time_payment?
    sub_item = subscription_item
    return false unless sub_item
    !sub_item.billable? # need to be stale, outside the time when we should have already processed payment
  end

  # Public: Returns true if this sponsorship represents a one-time payment from
  # the sponsor to the sponsorable.
  sig { returns T.nilable(T::Boolean) }
  def one_time_payment?
    async_one_time_payment?.sync
  end

  sig { returns Promise[T.nilable(T::Boolean)] }
  def async_one_time_payment?
    async_tier.then { |tier| tier&.one_time? }
  end

  # Public: Returns true if this sponsorship represents an invoiced payment that was made using an
  # InvoicedSponsorshipTransfer, NOT an invoiced payment made through a sponsorship-specific Zuora account.
  sig { returns T::Boolean }
  def manual_invoiced?
    invoiced_sponsorship_transfer.present?
  end

  # Public: Is this sponsorship one that was created via the manual invoicing process and it also has a previous
  # transfer (from the same sponsor, for the same maintainer) that occurred in the immediately preceding time
  # period?
  sig { returns T::Boolean }
  def manually_invoiced_consecutive_recurrence?
    manual_invoiced? && T.must(invoiced_sponsorship_transfer).consecutive_recurrence?
  end

  # Public: Check if this sponsorship has expired. Only applicable for one-time and invoiced
  # sponsorships. A user/org who makes a one-time payment to a maintainer will be counted as a
  # sponsor to that maintainer until the sponsorship expires.
  sig { returns T::Boolean }
  def expired?
    return false unless expires_at
    T.must(expires_at) < Date.current
  end

  # Public: Replace this sponsorship's subscription item as well as other properties as necessary. Will also enqueue
  # a job to remove the sponsor's access to any repository the sponsorship's tier granted.
  #
  # new_subscription_item - a Billing::SubscriptionItem that has subscribable_type=SponsorsTier
  #
  # Returns nothing. Raises ActiveRecord::RecordInvalid if the replacement fails.
  sig { params(new_subscription_item: Billing::SubscriptionItem).void }
  def update_subscription_item(new_subscription_item)
    new_tier = new_subscription_item.subscribable
    new_active = new_subscription_item.active?

    # Transferring sponsorships to enterprise-billing involves undefined ordering of when the org-billed
    # subscription items will be cancelled. Due to this, we need to handle the case that the org-billed
    # subscription items are cancelled after enterprise-billed sponsorships have been configured.
    #
    # The more generic behavior implemented is to no-op unless the cancelled sub item matches the sponsorship's
    # current sub item.
    is_cancellation = new_subscription_item.cancelled?
    same_sub_item = new_subscription_item.id == subscription_item_id
    if is_cancellation && !same_sub_item
      # avoid hydrating to check feature flag, transfers are org-only
      org_to_check = Organization.new(id: sponsor_id)
      return
    end

    update!(
      subscription_item: new_subscription_item,
      active: new_active,
      tier: new_tier,
      expires_at: expires_at_for(new_tier),
      subscribable_selected_at: subscribable_selected_at_for(new_tier),
    )

    after_deactivation unless new_active
  end

  # Public: Get a count of how many days we'll continue showing the sponsoring user/org
  # as the sponsor of the maintainer. Only applies to one-time sponsorships.
  #
  # Returns nil or an Integer. A negative value implies the sponsorship has already
  # expired.
  sig { returns T.nilable(Integer) }
  def days_remaining_till_expiration
    return unless expires_at

    current_time = Time.now.utc.beginning_of_day
    (T.must(expires_at) - current_time).to_i / 1.day
  end

  sig { returns T.nilable(T::Boolean) }
  def recurring_or_invoiced_payment?
    recurring_payment? || manual_invoiced?
  end

  # Public: Returns true if this sponsorship represents a recurring payment
  # from the sponsor to the sponsorable.
  sig { returns T.nilable(T::Boolean) }
  def recurring_payment?
    async_recurring_payment?.sync
  end

  sig { params(include_invoiced: T.nilable(T::Boolean)).returns(Promise[T.nilable(T::Boolean)]) }
  def async_recurring_payment?(include_invoiced: false)
    async_tier.then do |tier|
      if include_invoiced
        tier&.recurring? || tier&.invoiced?
      else
        tier&.recurring?
      end
    end
  end

  sig { returns T.nilable(T::Boolean) }
  def locked?
    tier&.locked_sponsorship?(active: active, selected_at: subscribable_selected_at)
  end

  # Public: Returns true for all non-invoiced sponsorships.
  # For legacy manual invoiced sponsorships, it checks what the user defined on the invoiced transfer.
  sig { returns T::Boolean }
  def send_new_sponsor_email?
    return true unless manual_invoiced?
    T.must(invoiced_sponsorship_transfer).send_new_sponsor_email_on_transfer?
  end

  # Public: No-op for all non-invoiced sponsorship.
  # For legacy manual invoiced sponsorships, we mark the time the new sponsor email was sent at.
  sig { returns T::Boolean }
  def new_sponsor_email_sent!
    return true unless manual_invoiced?
    T.must(invoiced_sponsorship_transfer).new_sponsor_email_sent!
  end

  # Public: Returns a sponsor-defined note to include in the new sponsor email.
  sig { returns T.nilable(String) }
  def new_sponsor_email_note
    return unless manual_invoiced?
    T.must(invoiced_sponsorship_transfer).new_sponsor_email_note
  end

  # Public: Returns the sponsorship amount based on the sponsor's plan cycle.
  #
  # :include_fees - Optional Boolean. Whether to include sponsorship fees in the price. Defaults to false.
  sig { params(include_fees: T::Boolean).returns(T.nilable(Billing::Money)) }
  def amount(include_fees: false)
    # we always look at the yearly price for invoiced sponsorships since this
    # is the amount that actually got transferred. the monthly price is used
    # to have an accurate representation of the monthly value of the sponsorship
    # to populate our dashboards.
    duration = if manual_invoiced?
      :year
    else
      sponsor&.sponsors_plan_duration
    end

    if include_fees
      tier&.base_price(duration: duration, include_fees: include_fees, subscription_item: subscription_item)
    else
      tier&.base_price(duration: duration, include_fees: false)
    end
  end

  sig { returns Integer }
  def monthly_price_in_cents
    return 0 unless tier
    T.must(tier).monthly_price_in_cents
  end

  # Public: Check if the sponsor in this sponsorship has opted into receiving emails from the sponsorable. Only
  # returns the actual true/false result when the viewer is allowed to know.
  #
  # viewer - currently authenticated User or nil
  #
  # Returns a Promise resolving to either a Boolean or nil.
  sig { params(viewer: T.nilable(User)).returns(Promise[T.nilable(T::Boolean)]) }
  def async_is_sponsor_opted_into_email_for(viewer)
    return Promise.resolve(T.let(nil, T.nilable(T::Boolean))) unless viewer

    is_readable_promise = async_sponsorable_adminable_by?(viewer).then do |is_readable_as_sponsorable|
      next true if is_readable_as_sponsorable

      async_adminable_by?(viewer)
    end

    is_readable_promise.then do |is_readable|
      if is_readable
        is_sponsor_opted_in_to_email?
      end
    end
  end

  # Public: Get how much money this sponsorship costs on a recurring basis, in US cents, if the
  # given user has permission to know this.
  #
  # viewer - the currently authenticated User
  # include_invoiced - Boolean indication whether to include non-Zuora invoiced sponsorships in the calculation
  #
  # Returns a Promise resolving to an Integer. Resolves to 0 when the given viewer is not privy
  # to the value of this sponsorship, or when this sponsorship is for a one-time payment.
  sig { params(viewer: T.nilable(User), include_invoiced: T.nilable(T::Boolean)).returns(Promise[Integer]) }
  def async_recurring_monthly_price_in_cents_for(viewer, include_invoiced: false)
    async_recurring_payment?(include_invoiced: include_invoiced).then do |is_recurring|
      next 0 unless is_recurring

      async_amount_readable_by?(viewer).then do |is_readable|
        next 0 unless is_readable
        monthly_price_in_cents
      end
    end
  end

  sig { returns T.any(Integer, BigDecimal) }
  def monthly_price_in_dollars
    return 0 unless tier
    T.must(tier).monthly_price_in_dollars
  end

  # Public: Returns a String representation of the sponsorship amount per cycle.
  sig { returns(String) }
  def amount_per_cycle
    if manual_invoiced? || one_time_payment?
      "$#{amount} one time"
    else
      "$#{amount} / #{sponsor&.sponsors_plan_duration}"
    end
  end

  sig { returns T.nilable(T::Boolean) }
  def from_organization?
    sponsor&.organization?
  end

  # Public: Was this recipient of this sponsorship an organization?
  sig { returns T.nilable(T::Boolean) }
  def to_organization?
    sponsorable&.organization?
  end

  # Public: Was this recipient of this sponsorship a user?
  sig { returns T.nilable(T::Boolean) }
  def to_user?
    sponsorable&.user?
  end

  sig { returns T.nilable(T::Boolean) }
  def custom_tier?
    tier&.custom?
  end

  sig { returns T.nilable(User) }
  def tier_creator
    tier&.creator
  end

  # Public: return the date the subscribable was selected in the local/Zuora time zone
  sig { returns Date }
  def tier_selected_date
    (subscribable_selected_at || created_at || Time.current).localtime.to_date
  end

  # Public: whether the tier was selected prior to a given date.
  #
  # date - the Date to compare with the date the subscribable was selected.
  sig { params(date: Date).returns(T::Boolean) }
  def tier_selected_on_or_before?(date)
    tier_selected_date <= date
  end

  # Public: Get the sponsor user/org if their identity can be known by the given viewer.
  #
  # viewer - currently authenticated User or nil
  sig { params(viewer: T.nilable(User)).returns(Promise[T.nilable(T.any(User, Organization))]) }
  def async_sponsor_entity(viewer:)
    self.actor = viewer

    async_sponsor_readable_by?(viewer).then do |is_sponsor_readable|
      async_linked_or_direct_sponsor if is_sponsor_readable
    end
  end

  # Public: Add a background job to the queue that will send an email to a sponsor to inform them that their
  # sponsorship is pending.
  sig { void }
  def enqueue_pending_sponsorship_email_job
    return unless pending?

    if GitHub.flipper[:sponsors_pending_sponsorships].enabled?(sponsor)
      SendPendingSponsorshipEmailJob.perform_later(self)
    end
  end

  # Public: Add a background job to the queue that will revoke the sponsor's access to the repository this sponsorship
  # granted access to, if any.
  sig { void }
  def enqueue_revoke_repository_access_job
    sponsorship_repository&.enqueue_revoke_access_job
  end

  # Public: Is this a payment for the current sponsorship, or a payment in addition to
  # the current sponsorship?
  #
  # tier_paid: SponsorTier the payment is referencing
  sig { params(tier_paid: T.nilable(SponsorsTier)).returns(T::Boolean) }
  def concurrent_payment?(tier_paid:)
    return false unless self[:subscribable_id]
    return false unless tier_paid&.one_time?
    return false unless recurring_payment?
    tier_paid.sponsors_listing == sponsors_listing
  end

  sig { void }
  def enqueue_grant_repository_access_job
    tier&.enqueue_grant_repository_access_job_for(sponsor_id)
  end

  sig { returns T.nilable(Integer) }
  def sponsors_listing_id
    if association(:sponsors_listing).loaded?
      sponsors_listing&.id
    else
      tier&.sponsors_listing_id
    end
  end

  # Public: Get the active goal the maintainer receiving this sponsorship is working toward, if any.
  #
  # Examples
  #
  #   # To prevent N+1s when this method is called on a list of Sponsorship records, prefill it this way:
  #
  #   # Execute 1 query to preload (usually in a controller action):
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :active_goal)
  #
  #   sponsorships.each do |sponsorship|
  #     # Method is preloaded and memoized -- no queries are executed here!
  #     sponsorship.active_goal
  #   end
  #
  # Returns a SponsorsGoal or nil.
  batch_method :active_goal do |sponsorships|
    sponsorable_ids = sponsorships.map(&:sponsorable_id).compact.uniq
    active_goals_by_sponsorable_id = {}

    if sponsorable_ids.any?
      goals = SponsorsGoal.active.for_sponsorable(sponsorable_ids).includes(:listing)
      active_goals_by_sponsorable_id = goals.each_with_object({}) do |goal, hash|
        sponsorable_id = goal.listing&.sponsorable_id
        hash[sponsorable_id] = goal # there can only be one active goal for a maintainer at a time
      end
    end

    sponsorships.each_with_object({}) do |sponsorship, hash|
      hash[sponsorship] = active_goals_by_sponsorable_id[sponsorship.sponsorable_id]
    end
  end

  sig { returns T::Boolean }
  def started_after_sponsors_public_release?
    return false unless subscribable_selected_at.present?

    T.must(subscribable_selected_at) >= SPONSORS_PUBLIC_RELEASE_DATE
  end

  # Public: calculate the fee to charge at time of payment for a sponsorship
  #
  # sponsor - the User or Organization making the payment
  # flat_price - Billing::Money object representing the base price of the sponsorship
  #
  # Returns a Billing::Money
  sig { params(sponsor: T.nilable(T.any(User, Organization)), flat_price: Billing::Money).returns(Billing::Money) }
  def self.fee_at_sponsorship_payment_time_for(sponsor:, flat_price:)
    if sponsor&.should_pay_fees_at_sponsorship_payment_time?
      fee_for_credit_card_org_sponsorship_at(flat_price)
    else
      Billing::Money.zero
    end
  end

  # Public: calculate the fee to charge for a credit card organization's sponsorship
  #
  # flat_price - Billing::Money object representing the base price of the sponsorship
  sig { params(flat_price: Billing::Money).returns(Billing::Money) }
  def self.fee_for_credit_card_org_sponsorship_at(flat_price)
    flat_price * PERCENT_SPONSORSHIP_FEE_FOR_CREDIT_CARD_ORGS / BigDecimal(100)
  end

  # Public: calculate the fee an invoiced org should pay on top of a flat price
  sig { params(flat_price: Billing::Money).returns(Billing::Money) }
  def self.fee_for_invoiced_org_payment_at(flat_price)
    flat_price * PERCENT_SPONSORSHIP_FEE_FOR_INVOICED_ORGS / BigDecimal(100)
  end

  sig { returns T.nilable(T.any(User, Business, Organization)) }
  def billable_entity
    if subscription_item.present?
      T.must(subscription_item).account
    else
      sponsor
    end
  end

  sig { returns T.nilable(Date) }
  def next_billing_date
    billable_entity&.next_sponsors_billing_date
  end

  # Public: The date that this sponsorship will be activated, if this is a sponsorship
  #         that is scheduled for a future.
  sig { returns(T.nilable(Date)) }
  def pending_activation_date
    current_pending_change = pending_change
    return unless current_pending_change.present?
    return unless current_pending_change.type == Sponsorship::PendingChange::Type::Activation
    current_pending_change.active_on
  end

  private

  sig { params(old_expires_at: T.nilable(ActiveSupport::TimeWithZone)).returns(T.nilable(T::Boolean)) }
  def deactivate_subscription_item_or_restore_sponsorship_activeness(old_expires_at)
    success = subscription_item&.deactivate_without_callbacks

    unless success
      # Failed to deactivate the subscription item, so restore the sponsorship to keep it in sync:
      update_columns(active: true, expires_at: old_expires_at)
    end

    success
  end

  sig { void }
  def after_deactivation
    # if both the sponsor and sponsorable have Patreon set up, or if the sponsorship being cancelled was paid for on
    # Patreon, trigger a sync so we can update with the latest data from Patreon if applicable, since the cancelled
    # GitHub sponsorship may have been overriding it:
    if patreon? || sponsor&.sponsors_patreon_user
      sponsorable_patreon_user = sponsorable&.sponsors_patreon_user
      if sponsorable_patreon_user
        sponsorable_patreon_user.actor = actor
        sponsorable_patreon_user.sync_sponsors_patreon_user(include_sponsorships: true)
      end
    end

    enqueue_revoke_repository_access_job
  end

  sig { returns T::Boolean }
  def deactivate_and_expire_without_callbacks
    update_columns(active: false, expires_at: Time.now)
  end

  # Private: Calculate what this sponsorship's expiration time should be if its tier were to change to the given tier.
  #
  # new_tier - a SponsorsTier
  sig { params(new_tier: SponsorsTier).returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def expires_at_for(new_tier)
    # Recurring sponsorships have no expiration date:
    return unless new_tier.one_time?

    if tier == new_tier
      # Don't extend the expiration time if the tier wouldn't change:
      expires_at
    else
      # Calculate a new expiration time in the future since the tier would change:
      self.class.expiration_time
    end
  end

  # Private: Calculate what this sponsorship's tier selection time should be if its tier were to change to the given
  # tier.
  #
  # new_tier - a SponsorsTier
  sig { params(new_tier: SponsorsTier).returns(T.nilable(T.any(Time, ActiveSupport::TimeWithZone))) }
  def subscribable_selected_at_for(new_tier)
    if tier == new_tier
      # If the tier wouldn't change, don't modify the time that the tier was chosen:
      subscribable_selected_at
    else
      # Since the tier would change, would want to record the present time as when that tier change occurred:
      Time.now
    end
  end

  # Private: Check if the given viewer is either the sponsorable or an admin of the sponsorable, if the sponsorable
  # is an organization.
  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_sponsorable_adminable_by?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer
    return Promise.resolve(T.let(true, T::Boolean)) if viewer.id == sponsorable_id && viewer.user?

    async_sponsorable.then do |sponsorable|
      to_organization? && sponsorable.direct_admin_ids.include?(viewer.id)
    end
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_adminable_by?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) unless sponsor
    T.must(sponsor).async_sponsoring_parent_organization.then do
      adminable_by?(viewer)
    end
  end

  # Private: Normalize hash of metadata that came from the sponsorable to record details about where this
  # sponsorship came from.
  #
  # Requirements:
  #  - Maximum MAX_METADATA_PAIRS key-value pairs
  #  - Maximum MAX_METADATA_KEY_LENGTH characters per key
  #  - Maximum MAX_METADATA_VALUE_LENGTH characters per value
  #  - Remove metadata_ prefix
  #  - Remove non-alphanumeric characters from keys
  #  - Remove whitespaces and HTML tags from values
  #
  # Returns sanitized metadata
  sig { returns T.nilable(T::Hash[String, T.untyped]) }
  def sanitize_sponsorable_metadata
    if self.latest_sponsorable_metadata.present?
      filtered_metadata = self.latest_sponsorable_metadata
        .select { |key| key =~ METADATA_KEY_PREFIX_REGEX }
        .to_a.take(MAX_METADATA_PAIRS).to_h

      filtered_metadata.transform_keys! do |k|
        k = k.sub(METADATA_KEY_PREFIX_REGEX, "")
        k = ActionView::Base.full_sanitizer.sanitize(k)
        k = k.gsub(METADATA_NON_ALPHANUMERIC_REGEX, "").strip
        k[0, MAX_METADATA_KEY_LENGTH]
      end
      filtered_metadata.transform_values! do |v|
        v = ActionView::Base.full_sanitizer.sanitize(v)
        v = v.gsub(METADATA_NON_ALPHANUMERIC_REGEX, "").strip

        v[0, MAX_METADATA_VALUE_LENGTH]
      end

      sanitized_metadata = filtered_metadata.delete_if { |k, v| empty_or_invalid_data?(k, v) }
      sanitized_metadata = nil unless sanitized_metadata.present?
    end

    self.latest_sponsorable_metadata = sanitized_metadata
  end

  sig { params(k: String, v: String).returns(T.nilable(T::Boolean)) }
  def empty_or_invalid_data?(k, v)
    k.empty? || v.empty? || invalid_metadata?(k, v)
  end

  sig { params(key: String, value: String).returns(T.nilable(T::Boolean)) }
  def invalid_metadata?(key, value)
    Sponsors::ProfaneLanguageCheck.call(key) || Sponsors::ProfaneLanguageCheck.call(value)
  end

  sig { void }
  def tier_and_sponsorable_agree
    return unless tier && sponsorable

    unless T.must(tier).sponsorable == sponsorable
      errors.add(:subscribable_id, "is not @#{sponsorable}'s")
    end
  end

  sig { returns T::Boolean }
  def is_being_activated?
    !active_was && active
  end

  sig { returns T::Boolean }
  def was_activated?
    return false if active_previously_was.nil?
    !active_previously_was && active
  end

  # is this a github sponsorship that overrode an active patreon sponsorship?
  sig { returns T::Boolean }
  def overrode_patreon_sponsorship?
    payment_source_previously_was == "patreon" && payment_source == "github"
  end

  sig { returns T.nilable(T::Boolean) }
  def was_locked?
    tier_was&.locked_sponsorship?(active: active_was,
      selected_at: subscribable_selected_at_was)
  end

  sig { returns T.nilable(SponsorsTier) }
  def tier_was
    return unless subscribable_id_was
    SponsorsTier.find_by(id: subscribable_id_was)
  end

  sig { returns T.nilable(T::Boolean) }
  def manual_invoiced_or_one_time?
    manual_invoiced? || one_time_payment?
  end

  sig { returns T.nilable(T::Boolean) }
  def same_one_time_payment_selected_again?
    one_time_payment? && is_being_activated?
  end

  sig { returns T.nilable(T::Boolean) }
  def first_time_sponsor?
    # If the sponsorship was previously inactive and is now active, this isn't the
    # first time you've sponsored anyone:
    return false if was_activated?
    return false if overrode_patreon_sponsorship?
    sponsor&.first_time_sponsor?(new_sponsorship: self)
  end

  sig { returns T.nilable(T::Boolean) }
  def first_time_sponsorable?
    # If the sponsorship was previously inactive and is now active, this isn't the
    # first time you've been the recipient:
    return false if was_activated?
    return false if overrode_patreon_sponsorship?
    sponsorable&.first_time_sponsorable?(new_sponsorship: self)
  end

  sig { void }
  def check_active_goal_completion
    goal = active_goal

    return if goal.blank?
    if goal.can_complete?
      CompleteSponsorsGoalJob.perform_later(goal)
    elsif goal.near_complete?
      goal.instrument_near_complete_event
    end
  end
end
