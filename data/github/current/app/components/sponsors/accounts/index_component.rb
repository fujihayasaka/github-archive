# typed: true
# frozen_string_literal: true

class Sponsors::Accounts::IndexComponent < ApplicationComponent
  # sponsors_accounts - an Array of Users and Organizations with their SponsorsListing already loaded
  def initialize(sponsors_accounts:)
    @sponsors_accounts = sponsors_accounts
  end

  private

  def render?
    sponsors_accounts.any?
  end

  memoize def sponsors_accounts
    @sponsors_accounts.reject do |user_or_org|
      user_or_org.sponsors_listing&.sdn_disabled?
    end
  end

  memoize def accepted_accounts
    sponsors_accounts.select(&:sponsors_program_member?)
  end

  memoize def submitted_accounts
    sponsors_accounts.select(&:sponsors_waitlisted?)
  end

  memoize def unsubmitted_accounts
    sponsors_accounts.reject(&:sponsors_listing)
  end
end
