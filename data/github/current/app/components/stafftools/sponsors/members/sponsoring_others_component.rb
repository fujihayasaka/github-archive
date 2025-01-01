# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::SponsoringOthersComponent < ApplicationComponent
  SPONSORSHIPS_LIMIT = 10

  # sponsorable - a User or Organization
  def initialize(sponsorable:)
    @sponsorable = sponsorable
  end

  memoize def render?
    sponsorable.present? && total_count > 0
  end

  private

  attr_reader :sponsorable

  memoize def sponsorships
    sponsorable
      .active_sponsorships_as_sponsor_relation
      .includes(:sponsorable)
      .order(:id)
      .limit(SPONSORSHIPS_LIMIT)
      .to_a
  end

  memoize def total_count
    sponsorable.sponsoring_count(include_private: true)
  end

  memoize def overflow_count
    total_count - sponsorships.size
  end

  def sentence
    sponsoring_links = sponsorships.map do |sponsorship|
      link_to(sponsorship.sponsorable, stafftools_sponsors_member_path(sponsorship.sponsorable))
    end

    sponsoring_others_sentence = html_safe_to_sentence(sponsoring_links)

    if overflow_count > 0
      sponsoring_others_sentence << " and #{pluralize(overflow_count, "other")}"
    end

    sponsoring_others_sentence
  end
end
