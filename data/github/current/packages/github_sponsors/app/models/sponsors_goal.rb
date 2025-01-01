# typed: strict
# frozen_string_literal: true

require_relative "sponsors/k_v"

class SponsorsGoal < ApplicationRecord::Domain::Sponsors
  include Instrumentation::Model
  include Workflow

  extend GitHub::Encoding
  force_utf8_encoding :description

  enum :kind, {
    total_sponsors_count: 0,
    monthly_sponsorship_amount: 1,
  }

  # rubocop:todo Rails/InverseOf
  belongs_to :listing,
    required: true,
    class_name: :SponsorsListing,
    foreign_key: :sponsors_listing_id
  # rubocop:enable Rails/InverseOf

  has_one :sponsorable, through: :listing, disable_joins: true

  has_many :contributions,
    dependent: :destroy,
    class_name: :SponsorsGoalContribution

  scope :with_states, ->(*states) do
    state_values = states.map { |state| workflow_spec.states[state.to_sym]&.value }
    where(state: state_values)
  end

  scope :active, -> { with_states(:active) }
  scope :completed, -> { with_states(:completed) }

  scope :for_sponsorable, ->(sponsorable_or_id) do
    joins(:listing).where(sponsors_listings: { sponsorable_id: sponsorable_or_id })
  end

  # The `target_value` column has a limit of 4 bytes to store a **signed** integer.
  # That means that the maximum number we can represent is:
  #
  # 8 (bits per byte) * 4 (bytes) = 32
  # 32 bits - 1 (to represent the sign: negative vs positive) = 31
  # 2**31 = 2_147_483_648
  #
  # NOTE: We don't have a reason to limit this number other than to avoid an exception.
  # We have the ability to increase the byte limit in the future if needed.
  MAX_TARGET_VALUE = 2_147_483_648

  # We want to limit goal descriptions so they are concise and have a better UI treatment.
  # This was an arbitrary limit chosen based on the current value of
  # SponsorsTier::MAX_DESCRIPTION_LENGTH. It can be increased if necessary.
  MAX_DESCRIPTION_LENGTH = 750

  # The threshold at which a goal is considered "near complete".
  NEAR_COMPLETE_THRESHOLD = 80

  validates :target_value, presence: true, numericality: {
    only_integer: true,
    greater_than: 0,
    less_than: MAX_TARGET_VALUE,
  }

  validates :description, presence: true, length: { maximum: MAX_DESCRIPTION_LENGTH }
  validate :only_one_active_goal, if: :active?
  validate :not_already_completed, if: :active?

  workflow :state do
    state :active, 0 do
      event :complete, transitions_to: :completed, if: :achieved?
      event :retire, transitions_to: :retired
    end

    state :completed, 1
    state :retired, 2
  end

  # Public: Get the active goal for the specified sponsorable.
  sig { params(sponsorable_id: Integer).returns(T.nilable(SponsorsGoal)) }
  def self.active_goal_for(sponsorable_id:)
    active.for_sponsorable(sponsorable_id).first
  end

  # Public: Get the current standing of the goal, how far along the Sponsors member is to
  # reaching it. Returns a dollar amount for monthly sponsorship-type goals, returns a count
  # of sponsors for total sponsors-type goals.
  sig { returns(Integer) }
  def current_value
    @current_value ||= T.let(
      if monthly_sponsorship_amount?
        subscription_value / 100
      else
        sponsors_count
      end,
    T.nilable(Integer))
  end

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  # Public: Is an actor able to view this goal?
  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_readable_by?(actor)
    async_listing.then do
      next true if publicly_visible?
      next false unless actor.present?
      next true if actor.can_admin_sponsors_listings?

      async_adminable_by?(actor)
    end
  end

  sig { returns(T::Boolean) }
  def publicly_visible?
    return false unless active?

    this_listing = listing
    return false unless this_listing.present?

    this_listing.approved?
  end

  # Public: Indicates if a given actor has admin access to this goal.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def adminable_by?(actor)
    async_adminable_by?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_adminable_by?(actor)
    async_listing.then do |listing|
      next false unless listing.present?
      listing.async_adminable_by?(actor)
    end
  end

  sig { returns(T::Boolean) }
  def for_organization?
    this_sponsorable = sponsorable
    return false unless this_sponsorable.present?

    this_sponsorable.organization?
  end

  sig { returns(Integer) }
  def percent_complete
    return 0 if target_value.to_i.zero?

    percent = current_value * 100 / target_value
    # encourage users by rounding up to 1% if current value is at least 1
    percent = 1 if current_value.positive? && percent == 0

    [100, percent].min
  end

  sig { returns(String) }
  def title
    if monthly_sponsorship_amount?
      total_cents = target_value * 100
      "#{Billing::Money.new(total_cents).format(no_cents: true)} per month"
    else
      "#{target_value} monthly #{"sponsor".pluralize(target_value)}"
    end
  end

  sig { returns(String) }
  def formatted_current_value
    if monthly_sponsorship_amount?
      total_cents = current_value * 100
      Billing::Money.new(total_cents).format(no_cents: true)
    else
      current_value.to_s
    end
  end

  sig { returns(Promise[T.nilable(GitHubSponsors::Types::Sponsorable)]) }
  def async_target_for_conditional_access
    async_listing.then do |listing|
      next unless listing.present?
      listing.async_target_for_conditional_access
    end
  end

  sig { returns(T.nilable(GitHubSponsors::Types::Sponsorable)) }
  def target_for_conditional_access
    listing&.target_for_conditional_access
  end

  # Public: Is this goal close to being completed?
  sig { returns(T::Boolean) }
  def near_complete?
    percent_complete >= NEAR_COMPLETE_THRESHOLD && percent_complete < 100
  end

  sig { void }
  def instrument_near_complete_event
    return if near_complete_event_at.present?

    GlobalInstrumenter.instrument("sponsors.goal_event", {
      listing: listing,
      goal: self,
      action: :NEAR_COMPLETED,
      sponsorable: sponsorable,
    })

    record_near_complete_event
  end

  private

  # Private: Indicates Whether the target value has been reached. This is meant to be a private method
  #          used only to manage state transitions. Public calls should rely on `can_complete?`
  #          or check if goal state is `completed?`.
  sig { returns(T::Boolean) }
  def achieved?
    return false if target_value.blank?

    if monthly_sponsorship_amount?
      (subscription_value / 100) >= target_value
    else
      sponsors_count >= target_value
    end
  end

  # Private: Returns the combined monthly recurring payments for active sponsorships
  #          received in the past 30 days, excluding prorated payments
  #          for this goal's Sponsors listing.
  sig { returns(Integer) }
  def subscription_value
    SponsorsListing.past_thirty_day_monthly_sponsorship_value_for(sponsors_listing_id)
  end

  sig { returns(Integer) }
  def sponsors_count
    Sponsorship.active.recurring.for_listing(sponsors_listing_id).count
  end

  sig { params(args: T.untyped, kwargs: T.untyped).void }
  def complete(*args, **kwargs)
    record_contributions
    touch(:completed_at)

    GlobalInstrumenter.instrument("sponsors.goal_event", {
      listing: listing,
      goal: self,
      action: :COMPLETED,
      sponsorable: sponsorable,
    })
  end

  sig { params(args: T.untyped, kwargs: T.untyped).void }
  def retire(*args, **kwargs)
    record_contributions
    touch(:retired_at)
  end

  sig { void }
  def record_contributions
    sponsorships = Sponsorship
      .active
      .recurring
      .for_listing(sponsors_listing_id)
      .order(created_at: :asc)
      .pluck(:sponsor_id, :subscribable_id)

    now = Time.current
    contribution_rows = sponsorships.map do |sponsor_id, tier_id|
      {
        sponsors_goal_id: id,
        sponsor_id: sponsor_id,
        sponsors_tier_id: tier_id,
        created_at: now,
        updated_at: now,
      }
    end

    contributions.upsert_all(contribution_rows) if contribution_rows.any?
  end

  sig { void }
  def only_one_active_goal
    goals = self.class.active.where(sponsors_listing_id: sponsors_listing_id)
    goals = goals.where.not(id: id) if persisted?

    unless goals.empty?
      errors.add(:base, "Only one active goal can exist at a time.")
    end
  end

  sig { void }
  def not_already_completed
    return unless achieved?

    errors.add(:base, %{
      You already achieved this goal. Way to go!
      Try setting a different goal target.
    }.squish)
  end

  sig { returns(T.nilable(Time)) }
  def near_complete_event_at
    value = Sponsors::KV.store.get(near_complete_event_cache_key).value { nil }
    return unless value.present?

    Time.iso8601(value)
  rescue ArgumentError
    # ArgumentError gets raised if value is not a valid ISO8601 string
    # in this case we can safely ignore it and treat it as if the event was never triggered
    nil
  end

  sig { void }
  def record_near_complete_event
    ActiveRecord::Base.connected_to(role: :writing) do
      Sponsors::KV.store.set(
        near_complete_event_cache_key,
        Time.now.utc.iso8601,
        expires: 1.month.from_now,
      )
    end
  end

  sig { returns(String) }
  def near_complete_event_cache_key
    "sponsors_goal.near_complete_event.#{sponsors_listing_id}.#{id}"
  end
end
