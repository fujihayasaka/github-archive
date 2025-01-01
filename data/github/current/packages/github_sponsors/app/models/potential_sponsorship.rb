# typed: strict
# frozen_string_literal: true

class PotentialSponsorship < ApplicationRecord::Domain::Sponsors
  extend T::Sig
  include Workflow

  NOTICE = "potential_sponsorable_banner" # see config/notices.yml

  belongs_to :potential_sponsor, class_name: "User", required: true
  belongs_to :potential_sponsorable, class_name: "User", required: true,
    inverse_of: :potential_sponsorships_as_sponsorable
  belongs_to :created_by, class_name: "User", required: true

  validates :potential_sponsorable_id, uniqueness: { scope: :potential_sponsor_id }
  validate :potential_sponsorable_sponsors_listing_status, on: :create
  validate :potential_sponsor_and_potential_sponsorable_differ
  validate :created_by_and_potential_sponsorable_differ
  validate :potential_sponsorable_is_not_blocking
  validate :created_by_has_verified_email, on: :create
  validate :potential_sponsorable_is_not_spammy
  validate :potential_sponsor_is_not_spammy
  validate :potential_sponsorable_is_user_or_org
  validate :potential_sponsor_is_user_or_org

  after_commit :reset_notice_for_potential_sponsorable, on: :create

  workflow :state do
    state :pending, 0 do
      event :mark_as_sponsors_listing_created, transitions_to: :sponsors_listing_created
      event :acknowledge, transitions_to: :acknowledged
    end

    # Moves to this state when the potential sponsorable has dismissed the banner encouraging them to sign up for
    # Sponsors. Does not imply whether they will create a SponsorsListing or not.
    state :acknowledged, 1 do
      event :mark_as_sponsors_listing_created, transitions_to: :sponsors_listing_created
    end

    state :sponsors_listing_created, 2 do
      event :mark_as_sponsorship_created, transitions_to: :sponsorship_created
    end

    state :sponsorship_created, 3
  end

  scope :most_recent, -> { order(id: :desc) }
  scope :for_potential_sponsorable, ->(user_or_id) { where(potential_sponsorable_id: user_or_id) }
  scope :for_potential_sponsor, ->(user_or_id) { where(potential_sponsor_id: user_or_id) }
  scope :with_states, ->(*states) { where(state: states.compact.map { |state| state_value(state) }) }

  # Public: Get the Integer value matching a certain state.
  sig { params(name: T.any(String, Symbol)).returns(Integer) }
  def self.state_value(name)
    workflow_spec.states[name.to_sym]&.value
  end

  # Public: Get a human-readable description of the current state of the potential sponsorship.
  #
  # Returns a String.
  sig { returns(String) }
  def human_state
    if pending?
      "Pending"
    elsif acknowledged?
      "Acknowledged"
    elsif sponsors_listing_created?
      "Signed up for Sponsors"
    elsif sponsorship_created?
      "Sponsorship created"
    else
      "Unknown"
    end
  end

  private

  sig { void }
  def reset_notice_for_potential_sponsorable
    return unless pending?
    return unless potential_sponsorable

    if T.must(potential_sponsorable).user?
      T.must(potential_sponsorable).reset_notice(NOTICE)
    else
      T.must(potential_sponsorable).admins.each do |org_admin|
        org_admin.reset_notice(NOTICE)
      end
    end
  end

  sig { void }
  def potential_sponsorable_sponsors_listing_status
    return unless potential_sponsorable

    listing = T.must(potential_sponsorable).sponsors_listing
    return unless listing

    # Make sure the potential sponsorable lacks a Sponsors listing either because they haven't signed up or completed
    # something, and not that they're stuck waiting on us. We don't want to bother them if the ball is in our court.
    if listing.disabled?
      errors.add(:potential_sponsorable, "has a disabled Sponsors profile")
    elsif listing.approved?
      errors.add(:potential_sponsorable, "already has a public Sponsors profile")
    elsif listing.waitlisted? || listing.pending_approval?
      errors.add(:potential_sponsorable, "has signed up for Sponsors and is waiting on a response from GitHub")
    elsif listing.banned? || listing.sdn_disabled? || listing.spammy?
      errors.add(:potential_sponsorable, "had their Sponsors profile taken down")
    end
  end

  sig { void }
  def potential_sponsor_and_potential_sponsorable_differ
    if potential_sponsor_id == potential_sponsorable_id
      errors.add(:potential_sponsor, "can't be the same as potential sponsorable")
    end
  end

  sig { void }
  def created_by_and_potential_sponsorable_differ
    # Just sign up for Sponsors yourself, you don't have to log it first!
    if created_by_id == potential_sponsorable_id
      errors.add(:created_by, "can't be the same as potential sponsorable")
    end
  end

  sig { void }
  def potential_sponsorable_is_not_blocking
    return unless potential_sponsorable

    if T.must(potential_sponsorable).blocking?(created_by_id, potential_sponsor_id)
      errors.add(:base, "Cannot nudge #{potential_sponsorable} to create a GitHub Sponsors profile at this time.")
    end
  end

  sig { void }
  def created_by_has_verified_email
    return unless created_by

    if T.must(created_by).should_verify_email?
      errors.add(:created_by, "must have a verified email address")
    end
  end

  sig { void }
  def potential_sponsorable_is_not_spammy
    return unless GitHub.spamminess_check_enabled? && potential_sponsorable

    if T.must(potential_sponsorable).spammy?
      errors.add(:potential_sponsorable, "cannot be spammy")
    end
  end

  sig { void }
  def potential_sponsor_is_not_spammy
    return unless GitHub.spamminess_check_enabled? && potential_sponsor

    if T.must(potential_sponsor).spammy?
      errors.add(:potential_sponsor, "cannot be spammy")
    end
  end

  sig { void }
  def potential_sponsorable_is_user_or_org
    return unless potential_sponsorable

    # No bots
    unless T.must(potential_sponsorable).user? || T.must(potential_sponsorable).organization?
      errors.add(:potential_sponsorable, "must be a user or an organization")
    end
  end

  sig { void }
  def potential_sponsor_is_user_or_org
    return unless potential_sponsor

    # No bots
    unless T.must(potential_sponsor).user? || T.must(potential_sponsor).organization?
      errors.add(:potential_sponsor, "must be a user or an organization")
    end
  end
end
