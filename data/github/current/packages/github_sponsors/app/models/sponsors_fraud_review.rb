# typed: true
# frozen_string_literal: true

class SponsorsFraudReview < ApplicationRecord::Domain::Sponsors
  belongs_to :sponsors_listing
  belongs_to :reviewer, class_name: "User", required: false
  has_many :fraud_flagged_sponsors, autosave: true, dependent: :destroy

  after_create_commit :disable_payouts_for_listing
  after_create_commit :instrument_creation
  after_commit :instrument_state_change, if: :saved_change_to_state?

  scope :filter_by_state, ->(state) do
    where(state: state.to_s) if state
  end

  scope :ordered_by, ->(sort_by) do
    case sort_by
    when "oldest"
      order(created_at: :asc)
    else
      order(created_at: :desc)
    end
  end

  scope :filter_by_sponsorable_login, ->(query) do
    if query.present?
      sanitized_query = "%#{ActiveRecord::Base.sanitize_sql_like(query.strip)}%"
      joins(:sponsors_listing).where("sponsors_listings.slug LIKE ?", sanitized_query)
    end
  end

  # Indicates the current state of the fraud review.
  #
  # pending - review is pending
  # resolved - reviewer determined the listing does not seem fraudulent
  # flagged - reviewer determined the listing is possibly fraudulent
  enum :state, { pending: 0, resolved: 1, flagged: 2 }

  # Public: Resolves this fraud review and reenables payouts, if they were
  #         disabled due to being fraud flagged.
  #
  # Returns a Boolean.
  def resolve(actor:)
    return true if resolved?

    if actor.blank?
      errors.add(:reviewer, "must be present")
      return false
    end

    unless pending?
      errors.add(:state, "must be pending")
      return false
    end

    unless sponsors_listing
      errors.add(:sponsors_listing, "does not exist")
      return false
    end

    success = update(
      state: :resolved,
      reviewer: actor,
      reviewed_at: Time.now,
    )

    if success
      listing = T.must(sponsors_listing)

      # delete any other pending fraud reviews for this listing in case they exist
      other_pending_fraud_reviews = listing.fraud_reviews.pending.where.not(id: self.id)
      other_pending_fraud_reviews.delete_all

      if listing.completed_payout_probation?
        listing.actor = actor
        listing.enable_payouts_for_active_stripe_connect_account
      end
    end

    success
  end

  # Public: Flags this fraud review as fraudulent and keeps payouts disabled.
  #
  # Returns a Boolean.
  def flag(actor:)
    return true if flagged?

    if actor.blank?
      errors.add(:reviewer, "must be present")
      return false
    end

    unless pending?
      errors.add(:state, "must be pending")
      return false
    end

    unless sponsors_listing
      errors.add(:sponsors_listing, "does not exist")
      return false
    end

    success = update(
      state: :flagged,
      reviewer: actor,
      reviewed_at: Time.now,
    )

    if success
      # delete any other pending fraud reviews for this listing in case they exist
      other_pending_fraud_reviews = T.must(sponsors_listing).fraud_reviews.pending.where.not(id: self.id)
      other_pending_fraud_reviews.delete_all
    end

    success
  end

  # Public: Reverts a review to the pending state, and disables payouts again
  #         until a new review is completed.
  #
  # Returns a Boolean.
  def revert_to_pending(actor:)
    return true if pending?

    if actor.blank?
      errors.add(:reviewer, "must be present")
      return false
    end

    success = update(
      state: :pending,
      reviewer: nil,
      reviewed_at: nil,
    )

    disable_payouts_for_listing if success

    success
  end

  private

  # Private: Enqueues a job to disable payouts for a listing until we can review
  #          it for fraud.
  def disable_payouts_for_listing
    return unless sponsors_listing&.completed_payout_probation?
    T.must(sponsors_listing).disable_payouts_for_active_stripe_connect_account(
      reason: "disabled for fraud review ##{id}",
    )
  end

  def instrument_creation
    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsors_fraud_review_create",
      fraud_review: self,
      listing: sponsors_listing,
      sponsorable: sponsors_listing&.sponsorable,
      listing_stafftools_metadata: sponsors_listing&.stafftools_metadata,
    )
  end

  def instrument_state_change
    GlobalInstrumenter.instrument("sponsors.sponsors_fraud_review_state_change", {
      fraud_review: self,
      previous_state: state_before_last_save,
      reviewer: reviewer,
      sponsorable: sponsors_listing&.sponsorable,
      reviewed_at: reviewed_at,
    })
  end
end
