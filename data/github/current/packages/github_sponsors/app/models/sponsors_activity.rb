# typed: true
# frozen_string_literal: true

class SponsorsActivity < ApplicationRecord::Domain::Sponsors
  # These are offsets relative to Date.today used to find the beginning
  # of a time period for a sponsors activity timeline:
  #
  # - :day goes back zero days (only today)
  # - :week goes back 6 days (7 days including today)
  # - :month goes back 29 days (30 days including today)
  # - :year goes back 365 days (365 days including today)
  PERIOD_OFFSET_MAPPING = { day: 0, week: 6, month: 29, year: 365 }.freeze
  DEFAULT_PERIOD = :alltime
  VALID_PERIODS = [:day, :week, :month, :year, DEFAULT_PERIOD].freeze

  # Public: How often is it okay to send an email about a particular sponsorship event to the same user?
  EMAIL_FREQUENCY_IN_MINUTES = 15

  belongs_to :sponsorable, class_name: "User", inverse_of: :sponsors_activities
  belongs_to :sponsor, class_name: "User", inverse_of: :sponsors_activities_as_sponsor
  belongs_to :sponsors_tier
  belongs_to :old_sponsors_tier, class_name: "SponsorsTier"
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  belongs_to :old_repository, class_name: "Repository"
  belongs_to :sponsors_listing, foreign_key: :sponsorable_id, primary_key: :sponsorable_id, inverse_of: :activities
  # N.B. `sponsors_patreon_user` returns the current SponsorsPatreonUser associated with the sponsor (if one exists),
  # and not the SponsorsPatreonUser that existed when this activity was generated.
  has_one :sponsors_patreon_user, through: :sponsor, disable_joins: true

  # Public: Only activities with these actions should be visible to the sponsorable.
  ACTIONS_FOR_SPONSORABLE = %w(new_sponsorship cancelled_sponsorship tier_change refund pending_change
    sponsor_match_disabled).freeze

  # Public: Only activities with these actions should be visible to the sponsor.
  ACTIONS_FOR_SPONSOR = %w(new_sponsorship cancelled_sponsorship tier_change refund pending_change).freeze

  # Public: What kind of event occurred that this activity represents?
  #
  # Do NOT reorder values in this array, as the index corresponds to the integer value stored in the database.
  # If you reorder or remove values, you change the meaning of existing database records. Appending new values is
  # fine.
  enum :action, [
    # sponsorship is created with a successful prorated transaction
    :new_sponsorship,
    # existing sponsorship is cancelled by a pending change
    :cancelled_sponsorship,
    # sponsorship tier changed directly by sponsor (upgrade) or by a
    # scheduled/pending change (downgrade)
    :tier_change,
    # funds from a previous transaction have been refunded to the
    # sponsor and/or GitHub (match). Currently sourced from
    # SponsorshipTransferReversal events.
    :refund,
    # a downgrade or cancellation is scheduled for the start of the
    # sponsor's next billing cycle
    :pending_change,
    # a previously matched sponsorship will no longer be matched going forward
    :sponsor_match_disabled
  ], prefix: :is

  enum :payment_source, {
    github: 0,
    patreon: 1
  }

  validates :sponsorable, :action, :timestamp, presence: true
  validates :sponsors_tier, presence: true, unless: :is_pending_change?
  validates :old_sponsors_tier, presence: true, if: -> do
    T.bind(self, SponsorsActivity)
    is_pending_change? || is_tier_change?
  end

  after_commit :enqueue_sponsorship_emails_job, on: :create, if: :is_new_sponsorship?
  after_commit :enqueue_grant_repo_access_job, on: :create, if: :is_new_sponsorship?
  after_commit :enqueue_revoke_repo_access_job, on: :create, if: :is_tier_change?
  after_commit :enqueue_sponsorship_cancellation_email_job, on: :create, if: :is_cancelled_sponsorship?
  after_commit :enqueue_sponsorship_upgrade_email, on: :create, if: :is_upgrade?

  scope :by_timestamp, -> { order(timestamp: :desc).order(id: :desc) }
  scope :oldest_first, -> { order(timestamp: :asc).order(id: :asc) }

  scope :for_sponsorable, ->(user_or_id) { where(sponsorable_id: user_or_id) }
  scope :for_sponsor, ->(user_or_id) { where(sponsor_id: user_or_id) }
  scope :for_sponsorable_and_sponsor, ->(sponsorable_or_id, sponsor_or_id) do
    for_sponsorable(sponsorable_or_id).for_sponsor(sponsor_or_id)
  end
  scope :for_sponsorable_or_sponsor, ->(user_or_id) { for_sponsorable(user_or_id).or(for_sponsor(user_or_id)) }
  scope :with_sponsorable_action, -> { with_actions(ACTIONS_FOR_SPONSORABLE) }
  scope :with_sponsor_action, -> { with_actions(ACTIONS_FOR_SPONSOR) }
  scope :one_time, -> { joins(:sponsors_tier).merge(SponsorsTier.one_time) }
  scope :with_sponsors_tier, ->(sponsors_tier_or_id) { where(sponsors_tier_id: sponsors_tier_or_id) }

  scope :with_actions, ->(*actions) { where(action: actions) }

  # Public: Preloads the relations used in `Sponsors::Activities::ActivityComponent` to avoid n+1 queries when
  # passing each activity record from a list of activities to the component.
  sig do
    params(activities: T.any(ActiveRecord::Relation, T::Array[SponsorsActivity], WillPaginate::Collection)).void
  end
  def self.preload_for_activity_component(activities)
    GitHub::PrefillAssociations.prefill_associations(activities, [:sponsors_listing, :old_sponsors_tier,
      :sponsors_tier, :repository, :old_repository])

    user_ids = (activities.map(&:sponsorable_id) + activities.map(&:sponsor_id)).uniq
    users = if user_ids.present?
      User.where(id: user_ids).to_a
    end
    GitHub::PrefillAssociations.prefill_associations(activities, :sponsor, available_records: users)
    things_with_sponsorable = activities.map(&:sponsors_listing) + activities
    GitHub::PrefillAssociations.prefill_associations(things_with_sponsorable, :sponsorable,
      available_records: users)

    GitHub::PrefillAssociations.prefill_batch_method(activities, :async_linked_or_direct_sponsor)
    org_sponsors = activities.map(&:linked_or_direct_sponsor).select(&:organization?)
    GitHub::PrefillAssociations.prefill_associations(org_sponsors, :business)
  end

  # Public: Get all activity that's visible to the given user.
  #
  # viewer - a User or nil
  #
  # Returns an ActiveRecord::Relation of SponsorsActivity.
  scope :visible_to, ->(viewer) do
    if viewer
      owned_org_ids = viewer.owned_organization_ids
      billing_managed_org_ids = viewer.billing_manager_organization_ids

      # Activities visible to the viewer because the viewer is the admin of a Sponsors listing:
      viewer_and_owned_org_ids = [viewer.id] + owned_org_ids
      activities_for_sponsorable = for_sponsorable(viewer_and_owned_org_ids).with_sponsorable_action

      # Activities visible to the viewer because the viewer is the sponsor, is an admin of a sponsoring org,
      # or is the admin of an org who gets the credit for sponsorships from a linked org:
      viewer_and_billing_managed_org_ids = viewer_and_owned_org_ids + billing_managed_org_ids
      linked_org_sponsor_ids = OrganizationProfile.for_organization(owned_org_ids + billing_managed_org_ids)
        .with_sponsoring_linked_organization_id
        .pluck(:sponsoring_linked_organization_id)
      activities_for_sponsor = for_sponsor(viewer_and_billing_managed_org_ids | linked_org_sponsor_ids)
        .with_sponsor_action

      activities_for_sponsorable.or(activities_for_sponsor)
    else
      none
    end
  end

  scope :for_period, -> (period) do
    if period == :alltime
      scoped
    else
      end_date = Date.current
      offset = PERIOD_OFFSET_MAPPING[period]
      start_date = end_date - offset.days
      start_time = start_date.beginning_of_day
      where(timestamp: start_time..)
    end
  end

  scope :filter_by_user_handle, ->(handle) do
    if handle.present?
      user_ids = User.search(handle.strip).pluck(:id)
      where(sponsor_id: user_ids)
    end
  end

  scope :filter_by_sponsors_action, ->(action) do
    where(action: action) if action.present?
  end

  scope :filter_by_current_tier, ->(tier_id) do
    where(sponsors_tier_id: tier_id) if tier_id.present?
  end

  scope :filter_by_old_tier, ->(tier_id) do
    where(old_sponsors_tier_id: tier_id) if tier_id.present?
  end

  scope :since, ->(date) { where(timestamp: date..) }
  scope :until, ->(date) { where(timestamp: ...date) }

  scope :filter_by_date, ->(date) do
    if date.present?
      timestamp = date.is_a?(String) ? DateTime.parse(date) : date
      start_time = timestamp.beginning_of_day
      end_time = timestamp.end_of_day
      where(timestamp: start_time..end_time)
    end
  end

  scope :with_currently_public_sponsorship, -> {
    sponsorships_table = Sponsorship.arel_table
    sponsors_activities_table = SponsorsActivity.arel_table

    sponsorships_join = sponsors_activities_table.join(sponsorships_table).on(
      sponsors_activities_table[:sponsor_id].eq(sponsorships_table[:sponsor_id]).and(
        sponsors_activities_table[:sponsorable_id].eq(sponsorships_table[:sponsorable_id])
      ).and(
        sponsorships_table[:privacy_level].eq(Sponsorship.privacy_levels["public"])
      )
    )

    joins(sponsorships_join.join_sources)
  }

  delegate :monthly_price_in_dollars, :monthly_price_in_cents, to: :sponsors_tier

  # Public: Get activities for pairs of sponsorables and sponsors.
  #
  # sponsorable_and_sponsor_pairs - an Array of Arrays with each child array
  #   having two elements: a User, Organization, or its ID that represents a
  #   sponsorable; and a User, Organization, or its ID that
  #   represents a sponsor; e.g., `[[22, 12], [28, 12], [22, 14]]`
  # time_range - optional Range of ActiveSupport::TimeZone to
  #   further refine which activities are returned
  #
  # Returns a Hash of Hashes of the format: `{ sponsorableID => { sponsorID => Array[SponsorsActivity] } }`
  sig do
    params(
      sponsorable_and_sponsor_pairs: T::Array[T::Array[T.any(GitHubSponsors::Types::Sponsor, Integer)]],
      time_range: T.nilable(Range)
    ).returns(T::Hash[Integer, T::Hash[Integer, T::Array[SponsorsActivity]]])
  end
  def self.for_sponsorables_and_sponsors(sponsorable_and_sponsor_pairs, time_range: nil)
    first_pair, *remaining_pairs = sponsorable_and_sponsor_pairs
    sponsorable, sponsor = first_pair
    activities = for_sponsorable_and_sponsor(sponsorable, sponsor)
    T.must(remaining_pairs).each do |(sponsorable, sponsor)|
      activities = activities.or(for_sponsorable_and_sponsor(sponsorable, sponsor))
    end
    activities = activities.where(created_at: time_range) if time_range
    result = {}
    activities.each do |sponsors_activity|
      sponsorable_id = sponsors_activity.sponsorable_id
      sponsor_id = sponsors_activity.sponsor_id
      result[sponsorable_id] ||= {}
      result[sponsorable_id][sponsor_id] ||= []
      result[sponsorable_id][sponsor_id] << sponsors_activity
    end
    result
  end

  # Public: Get the repository the sponsor should have been invited to join as a result of the event this activity
  # represents.
  sig { returns T.nilable(Repository) }
  def repository_sponsor_gained_access_to
    if is_new_sponsorship?
      repository
    elsif is_pending_change? || is_tier_change?
      repository unless repository_id == old_repository_id
    end
  end

  # Public: Get the repository the sponsor should have lost access to as a result of the event this activity
  # represents.
  sig { returns T.nilable(Repository) }
  def repository_sponsor_lost_access_to
    if is_cancelled_sponsorship?
      repository
    elsif is_pending_change? || is_tier_change?
      old_repository unless repository_id == old_repository_id
    end
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  sig { returns Promise[T.any(Symbol, GitHubSponsors::Types::Sponsorable)] }
  def async_target_for_conditional_access
    async_sponsorable.then do |sponsorable|
      next :no_target_for_conditional_access unless sponsorable
      sponsorable.async_target_for_conditional_access
    end
  end

  # Public: Was this activity generated by an organization sponsor?
  sig { returns T::Boolean }
  def from_organization?
    return false if sponsor.ghost? # we don't know who the real sponsor was
    sponsor.organization?
  end

  # Public: Is this activity for an organization's Sponsors listing?
  sig { returns T.nilable(T::Boolean) }
  def for_organization?
    sponsorable&.organization?
  end

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_readable_by?(actor)
    # Anonymous viewers can't see any activity:
    return Promise.resolve(T.let(false, T::Boolean)) unless actor

    # Can view activities involving your own Sponsors listing:
    return Promise.resolve(T.let(true, T::Boolean)) if actor.user? && sponsorable_id == actor.id && sponsorable_action?

    # Can view activities where you were the sponsor:
    return Promise.resolve(T.let(true, T::Boolean)) if actor.user? && sponsor_id == actor.id && sponsor_action?

    sponsorable_visibility_promise = async_sponsorable_adminable_by?(actor)
    sponsor_visibility_promise = async_sponsor_billing_manageable_by?(actor)

    # Based on what action this activity represents, see if the viewer can see it because they're the sponsorable
    # and the activity is meant for sponsorables, or because they're the sponsor and the activity is meant for
    # sponsors:
    if sponsor_action? && sponsorable_action?
      Promise.all([
        sponsorable_visibility_promise,
        sponsor_visibility_promise,
      ]).then do |(is_visible_to_sponsorable, is_visible_to_sponsor)|
        is_visible_to_sponsorable || is_visible_to_sponsor
      end
    elsif sponsor_action?
      sponsor_visibility_promise
    else
      sponsorable_visibility_promise
    end
  end

  sig { returns User }
  def sponsor
    super || User.ghost
  end

  sig { returns User }
  def linked_or_direct_sponsor
    async_linked_or_direct_sponsor.sync
  end

  sig { returns Promise[User] }
  def async_linked_or_direct_sponsor
    async_sponsor.then do |sponsor|
      next User.ghost unless sponsor
      next sponsor if sponsor.user?
      sponsor.async_sponsoring_parent_organization.then do |parent_org|
        parent_org || sponsor
      end
    end
  end

  sig { returns T::Boolean }
  def is_upgrade?
    if is_tier_change? || is_pending_tier_change?
      return false unless sponsors_tier && old_sponsors_tier
      T.must(sponsors_tier).monthly_price_in_dollars > T.must(old_sponsors_tier).monthly_price_in_dollars
    else
      false
    end
  end

  sig { returns T::Boolean }
  def is_increase?
    is_new_sponsorship? || is_upgrade?
  end

  sig { returns T::Boolean }
  def is_pending_cancellation?
    is_pending_change? && sponsors_tier_id.nil?
  end

  sig { returns T::Boolean }
  def is_pending_tier_change?
    is_pending_change? && sponsors_tier_id.present?
  end

  sig { returns T::Boolean }
  def one_time_tier?
    return false unless sponsors_tier
    T.must(sponsors_tier).one_time?
  end

  # Public: If this activity represents a sponsorship change to the tier, check if the previously used tier was
  # a one-time tier.
  sig { returns T::Boolean }
  def one_time_old_tier?
    return false unless old_sponsors_tier
    T.must(old_sponsors_tier).one_time?
  end

  # Public: Is the sponsorable associated with this activity currently untrusted as a sponsorable?
  sig { returns T.nilable(T::Boolean) }
  def untrusted_sponsorable?
    sponsorable&.untrusted_as_sponsorable?
  end

  # Public: Is the sponsor associated with this activity currently untrusted as a sponsor?
  sig { returns T::Boolean }
  def untrusted_sponsor?
    return false if sponsor.ghost? # we don't know who the real sponsor was
    sponsor.untrusted_as_sponsor?
  end

  # Public: Get the Sponsorship related to this SponsorsActivity, if one exists.
  #
  # Examples:
  #
  #   # To prevent N+1s when this method is called on a list of SponsorsActivity records,
  #   # prefill it this way:
  #
  #   # Execute few queries to preload, such as in a controller action:
  #   GitHub::PrefillAssociations.prefill_batch_method(sponsors_activities, :sponsorship)
  #
  #   sponsors_activities.each do |sponsors_activity|
  #     # Methods are preloaded and memoized - no queries are executed here!
  #     sponsors_activity.sponsorship
  #   end
  #
  # Returns a Sponsorship or nil.
  batch_method :sponsorship do |sponsors_activities|
    sponsors_activity_ids = sponsors_activities.map(&:id).compact

    sponsorships_table = Sponsorship.arel_table
    sponsors_activities_table = SponsorsActivity.arel_table

    activity_join = sponsorships_table.join(sponsors_activities_table).on(
      sponsorships_table[:sponsor_id].eq(sponsors_activities_table[:sponsor_id]).and(
        sponsorships_table[:sponsorable_id].eq(sponsors_activities_table[:sponsorable_id])
      )
    )

    sponsorships = Sponsorship.joins(activity_join.join_sources)
      .where(sponsors_activities_table[:id].in(sponsors_activity_ids))

    sponsorships_by_sponsor_sponsorable_pair = sponsorships.index_by do |sponsorship|
      Set[sponsorship.sponsor_id, sponsorship.sponsorable_id]
    end

    sponsors_activities.each_with_object({}) do |sponsors_activity, hash|
      lookup_key = Set[sponsors_activity.sponsor_id, sponsors_activity.sponsorable_id]
      hash[sponsors_activity] = sponsorships_by_sponsor_sponsorable_pair[lookup_key]
    end
  end

  # Public: Privacy level of the current sponsorship between the sponsor and maintainer
  #
  # This is the currenct privacy level and not the privacy level at the time the event was recorded.
  # Defining an interface for this supports communicating with maintainers about whether it's appropriate
  # to share sponsorship data about past events, since sponsors can modify their privacy level.
  #
  # Returns a Promise that resolves to a String ("public" or "private") or nil (if no sponsorship can be found)
  sig { returns Promise[String] }
  def async_current_privacy_level
    async_batch_sponsorship.then do |sponsorship|
      sponsorship&.privacy_level
    end
  end

  # Public: Find the activity with the same action, maintainer, and sponsor as this activity, as well as with the same
  # old and new tier if they're present on this activity, that most recently was created before this activity.
  sig { returns T.nilable(SponsorsActivity) }
  def most_recent_prior_similar_activity
    return unless GitHub.sponsors_enabled?
    activities = self.class.with_actions(action).for_sponsorable_and_sponsor(sponsorable_id, sponsor_id)
      .until(timestamp)
      .by_timestamp # descending order, so newest is first
      .filter_by_current_tier(sponsors_tier_id)
      .filter_by_old_tier(old_sponsors_tier_id)
    activities = activities.where.not(id: id) if persisted?
    activities.first
  end

  private

  sig { void }
  def enqueue_sponsorship_emails_job
    SendSponsorshipEmailsJob.perform_later(sponsors_activity: self)
  end

  sig { void }
  def enqueue_grant_repo_access_job
    sponsor_id, repo_id, tier_id = self.sponsor_id, repository_id, sponsors_tier_id
    return unless sponsor_id && repo_id && tier_id
    GrantSponsorsOnlyRepositoryAccessJob.perform_later(sponsor_id, repo_id, tier_id)
  end

  sig { void }
  def enqueue_revoke_repo_access_job
    return unless repository_sponsor_lost_access_to.present?
    RevokeSponsorsOnlyRepositoryAccessJob.perform_later(sponsor_id, old_repository_id, old_sponsors_tier_id)
  end

  sig { void }
  def enqueue_sponsorship_cancellation_email_job
    # ensure that if the cancellation is because of a
    # sponsorable unlinking their patreon account or disabling the `enabled_as_sponsorable` flag
    # we do not send the email
    return if patreon? && sponsorable && !T.must(sponsorable).sponsorable_via_patreon?

    SendSponsorshipCancellationEmailJob.perform_later(sponsors_activity: self)
  end

  sig { void }
  def enqueue_sponsorship_upgrade_email
    return unless sponsors_listing

    email_settings = T.must(sponsors_listing).email_opt_outs
    return if email_settings.opted_out_of_all? || email_settings.opted_out_of_upgrade_notices?

    SponsorsPrimerMailer.sponsorship_upgrade_notice(
      sponsorable: sponsorable,
      sponsorship: sponsorship,
      tier: sponsors_tier
    ).deliver_later
  end

  # Private: Is this activity one that's meant for the sponsorable to see?
  sig { returns T::Boolean }
  def sponsorable_action?
    ACTIONS_FOR_SPONSORABLE.include?(action)
  end

  # Private: Is this activity one that's meant for the sponsor to see?
  sig { returns T::Boolean }
  def sponsor_action?
    ACTIONS_FOR_SPONSOR.include?(action)
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_sponsorable_adminable_by?(actor)
    async_sponsorable.then do |sponsorable|
      next false unless sponsorable
      sponsorable.async_adminable_by?(actor)
    end
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_sponsor_billing_manageable_by?(actor)
    async_sponsor.then do |sponsor|
      next false unless sponsor&.organization?
      T.cast(sponsor, Organization).async_billing_manageable_by?(actor)
    end
  end
end
