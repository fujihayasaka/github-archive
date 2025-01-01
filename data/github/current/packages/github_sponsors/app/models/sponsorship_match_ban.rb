# typed: true
# frozen_string_literal: true

class SponsorshipMatchBan < ApplicationRecord::Domain::Sponsors
  include Instrumentation::Model

  belongs_to :sponsor, class_name: "User"
  belongs_to :sponsorable, class_name: "User", inverse_of: :sponsorship_match_bans_as_sponsorable

  validate :must_be_unique_for_sponsor_and_sponsorable

  # Public: Create a match ban between sponsorable and sponsor.
  #
  # sponsorable - The User sponsorable.
  # sponsor – The User sponsor.
  # actor - The User creating this match ban.
  #
  # Returns a SponsorshipMatchBan::Result.
  def self.create_for(sponsorable:, sponsor:, actor:)
    return Result.failure(errors: ["Sponsorable is required"]) if sponsorable.blank?
    return Result.failure(errors: ["Sponsor is required"]) if sponsor.blank?
    return Result.failure(errors: ["Actor is required"]) if actor.blank?

    record = sponsorable.sponsorship_match_bans_as_sponsorable.build(sponsor: sponsor)

    if record.save
      record.instrument :create, GitHub.guarded_audit_log_staff_actor_entry(actor)
      Result.success
    else
      Result.failure(errors: record.errors.full_messages)
    end
  end

  def sponsor_login
    sponsor&.login
  end

  # Public: Remove a match ban between sponsorable and sponsor.
  #
  # actor - The User removing this match ban.
  #
  # Returns a SponsorshipMatchBan::Result.
  def unban(actor:)
    return Result.failure(errors: ["Actor is required"]) if actor.blank?

    destroy

    if destroyed?
      instrument :destroy, GitHub.guarded_audit_log_staff_actor_entry(actor)
      Result.success
    else
      Result.failure(errors: errors.full_messages)
    end
  end

  class Result
    attr_reader :success, :errors
    alias_method :success?, :success

    # success – a Boolean indicating the success of an operation.
    # errors – an Array of String error messages.
    def initialize(success:, errors:)
      @success = success
      @errors = errors
    end

    def self.success
      new(success: true, errors: [])
    end

    def self.failure(errors:)
      new(success: false, errors: errors)
    end
  end

  private

  def must_be_unique_for_sponsor_and_sponsorable
    return unless SponsorshipMatchBan.find_by(sponsor: sponsor, sponsorable: sponsorable)
    errors.add(:sponsorable, "already does not receive matching for sponsorships from this sponsor")
  end

  def event_payload
    payload = { sponsorship_match_ban: self }
    payload.merge!(T.must(sponsorable).event_context) if sponsorable
    payload.merge!(T.must(sponsor).event_context(prefix: :sponsor)) if sponsor
    payload
  end
end
