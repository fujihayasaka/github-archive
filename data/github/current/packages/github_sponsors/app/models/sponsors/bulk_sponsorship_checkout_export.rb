# typed: true
# frozen_string_literal: true

module Sponsors
  class BulkSponsorshipCheckoutExport
    include ActiveModel::Validations

    SPONSORABLE_LOGIN_FIELD = Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD
    DOLLAR_AMOUNT_FIELD = Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD
    HEADERS = [SPONSORABLE_LOGIN_FIELD, DOLLAR_AMOUNT_FIELD].freeze

    validates :sponsor, :tiers_paid, presence: true

    def initialize(sponsor:, tiers_paid:)
      @sponsor = sponsor
      @tiers_paid = tiers_paid
    end

    def filename
      prefix = "github-sponsors-bulk-sponsorship"
      whose_export = "for-#{sponsor.login}"
      date = formatted_current_date_for(sponsor)
      extension = ".csv"
      parts = [prefix, whose_export, date]

      parts.join("-") + extension
    end

    def as_csv
      CSV.generate do |csv|
        csv << HEADERS
        tiers_paid.each do |tier|
          csv << HEADERS.map { |header| value_for(tier, header: header) }
        end
      end
    end

    private

    attr_reader :sponsor, :tiers_paid

    def value_for(tier_paid, header:)
      case header
      when SPONSORABLE_LOGIN_FIELD
        tier_paid.sponsorable_login
      when DOLLAR_AMOUNT_FIELD
        tier_paid.formatted_price_per_cycle(sponsor: sponsor)
      end
    end

    def formatted_current_date_for(sponsor)
      now = Time.now
      now = now.in_time_zone(sponsor.time_zone_name) if sponsor.time_zone_name
      now.strftime("%Y-%m-%d")
    end
  end
end
