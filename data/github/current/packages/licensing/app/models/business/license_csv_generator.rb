# typed: true
# frozen_string_literal: true

class Business::LicenseCsvGenerator

  attr_reader :business, :attributer, :urls

  def initialize(business)
    @business = business
    @attributer = Business::LicenseAttributer.new(business, options: { include_users_removed_this_cycle: true })
    @urls = ViewModel::URLs.new
  end

  def generate(options: {})
    CSV.generate do |csv|
      csv_rows(options: options).each do |row|
        csv << row.map { |cell| cell.is_a?(Array) ? cell.join(", ") : cell } # stop CSV from double-quoting array contents
      end
    end
  end

  def csv_rows(options: {})
    options = options.reverse_merge(exclude: [:two_factor_auth])

    license_usage_hash = attributer.license_usage_hash
    headers = license_usage_hash[:users].first&.keys || [] # we'll use this to generate our header row and use in values_at
    headers = headers - options[:exclude]
    [headers.map { |header| header.to_s }] + license_usage_hash[:users].each_with_object([]) do |user_hashes, rows|
      rows << user_hashes.values_at(*headers)
    end
  end
end
