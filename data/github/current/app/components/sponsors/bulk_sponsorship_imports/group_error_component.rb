# typed: true
# frozen_string_literal: true

class Sponsors::BulkSponsorshipImports::GroupErrorComponent < ApplicationComponent
  # sponsorship_rows - Array of Sponsors::BulkSponsorshipRow representing the
  #   rows from an imported CSV.
  # over_import_limit_rows - Array of Hashes of format [{ sponsorable_login: "login", amount: 1 }]
  #   where each Hash represents an unprocessed row imported from a CSV.
  def initialize(sponsorship_rows:, over_import_limit_rows:)
    @sponsorship_rows = sponsorship_rows
    @over_import_limit_rows = over_import_limit_rows
  end

  private

  attr_reader :sponsorship_rows, :over_import_limit_rows

  def render?
    sponsorship_rows.present? && GitHub.sponsors_enabled? && logged_in?
  end

  memoize def self_dealing_rows
    sponsorship_rows.select(&:self_dealing?)
  end

  memoize def non_sponsorable_rows
    sponsorship_rows.select(&:non_sponsorable?)
  end

  memoize def duplicated_rows
    sponsorship_rows.select(&:duplicate?)
  end

  memoize def locked_sponsorship_rows
    sponsorship_rows.select(&:locked_sponsorship?)
  end

  memoize def amount_over_limit_rows
    sponsorship_rows.select { |row| !row.login_missing? && row.amount_over_limit? }
  end

  memoize def amount_under_minimum_rows
    sponsorship_rows.select { |row| !row.login_missing? && row.amount_under_minimum? }
  end

  memoize def login_missing_rows
    sponsorship_rows.select(&:login_missing?)
  end

  memoize def conflicting_recurring_sponsorship_rows
    sponsorship_rows.select(&:conflicting_recurring_sponsorship?)
  end
end
