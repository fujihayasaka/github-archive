# typed: true
# frozen_string_literal: true

class Businesses::LicenseCountComponent < ApplicationComponent
  attr_reader :business, :consumed_licenses, :total_licenses

  def initialize(business:, consumed_licenses:, total_licenses: nil)
    @business          = business
    @consumed_licenses = consumed_licenses
    @total_licenses    = total_licenses
  end
end
