# typed: true
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipBlankTemplate
    SPONSORABLE_LOGIN_FIELD = Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD
    DOLLAR_AMOUNT_FIELD = Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD
    SAMPLE_SPONSORABLE_LOGINS = %w(maintainerUsername1 maintainerUsername2).freeze
    DOLLAR_AMOUNT_FIELD_EXAMPLE = "100 or $100"
    HEADERS = [SPONSORABLE_LOGIN_FIELD, DOLLAR_AMOUNT_FIELD].freeze

    def self.filename
      "bulk-sponsorships-template.csv"
    end

    def self.to_csv
      CSV.generate do |csv|
        csv << HEADERS
        SAMPLE_SPONSORABLE_LOGINS.each do |sample_login|
          csv << HEADERS.map do |header|
            case header
            when SPONSORABLE_LOGIN_FIELD then sample_login
            when DOLLAR_AMOUNT_FIELD then DOLLAR_AMOUNT_FIELD_EXAMPLE
            end
          end
        end
      end
    end
  end
end
