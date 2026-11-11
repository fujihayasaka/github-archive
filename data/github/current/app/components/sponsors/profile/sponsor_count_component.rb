# typed: true
# frozen_string_literal: true

class Sponsors::Profile::SponsorCountComponent < ApplicationComponent
  def initialize(sponsorable:, sponsor_count:, is_sponsoring:, is_new_sponsorship:)
    @sponsorable = sponsorable
    @sponsor_count = sponsor_count
    @is_sponsoring = fetch_or_fallback([true, false], is_sponsoring, false)
    @is_new_sponsorship = fetch_or_fallback([true, false], is_new_sponsorship, false)
  end

  def render?
    @sponsor_count > 0
  end

  def is_sponsoring?
    @is_sponsoring
  end

  def is_first_sponsorship?
    is_sponsoring? && @sponsor_count == 1
  end

  def is_new_sponsorship?
    is_sponsoring? && @is_new_sponsorship
  end

  def goal
    @sponsorable.sponsors_listing.active_goal
  end
end
