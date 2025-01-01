# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::MatchingStatusComponent < ApplicationComponent
  def initialize(listing:)
    @listing = listing
  end

  private

  def render?
    @listing.present?
  end

  def label_text
    matchable? ? "Matchable" : "Not matchable"
  end

  def label_class
    class_names(
      "Label",
      "Label--secondary",
      "Label--pink" => matchable?,
    )
  end

  def label_style
    return "" unless matchable?

    "border: 1px solid #f9b3dd;"
  end

  memoize def matchable?
    @listing.matchable?
  end

  memoize def reached_match_limit?
    @listing.reached_match_limit?
  end

  def matching_subtitle
    if matchable?
      matching_subtitle_for_matchable
    elsif @listing.match_disabled?
      "Matching is manually disabled"
    elsif @listing.for_organization?
      "Ineligible – sponsored organization"
    elsif !@listing.joined_waitlist_before_match_deadline?
      "Joined after match deadline"
    elsif reached_match_limit?
      "Reached match limit on #{@listing.match_limit_reached_at.strftime('%Y-%m-%d')}"
    elsif !@listing.published_in_last_year?
      "Published over a year ago"
    elsif !@listing.accepted_in_match_period?
      matching_period_in_months = SponsorsListing::DEFAULT_MATCHING_PERIOD_IN_MONTHS
      match_deadline = SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE.strftime("%b %d, %Y")

      "More than #{matching_period_in_months} months have passed since listing was accepted, and we are past the " +
        "match deadline of #{match_deadline}"
    else
      exception = ArgumentError.new("Unhandled reason for why listing is not matchable (#{@listing.id})")

      if Rails.env.production?
        Failbot.report(exception)
        "Unknown reason"
      else
        raise exception
      end
    end
  end

  def matching_subtitle_for_matchable
    if @listing.published_at
      end_date = (@listing.published_at + 1.year).strftime("%Y-%m-%d")
      "Matching period ends on #{end_date}"
    else
      "Matching period has not started"
    end
  end
end
