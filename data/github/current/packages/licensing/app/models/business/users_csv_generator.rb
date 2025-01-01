# typed: true
# frozen_string_literal: true

class Business::UsersCsvGenerator

  attr_reader :business, :attributer, :urls

  def initialize(business, license_attributer_options: { include_nonlicensed_roles: true })
    @business = business
    @business.billing_platform_client(timeout: 30.seconds.to_i) # use a longer billing platform timeout
    @attributer = Business::LicenseAttributer.new(business, options: license_attributer_options)
    @urls = ViewModel::URLs.new
  end

  def generate
    CSV.generate do |csv|
      csv_rows.each do |row|
        csv << row.map { |cell| cell.is_a?(Array) ? cell.join(", ") : cell } # stop CSV from double-quoting array contents
      end
    end
  end

  def csv_rows
    license_usage_hash = attributer.license_usage_hash
    headers = license_usage_hash[:users].first&.keys || [] # we'll use this to generate our header row and use in values_at
    [headers.map { |header| header.to_s.humanize }] + license_usage_hash[:users].each_with_object([]) do |user_hashes, rows|
      rows << user_hashes.values_at(*headers)
    end
  end
end
