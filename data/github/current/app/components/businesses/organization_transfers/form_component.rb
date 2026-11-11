# typed: true
# frozen_string_literal: true

class Businesses::OrganizationTransfers::FormComponent < ApplicationComponent
  attr_reader :transfer, :organization, :from_business

  def initialize(transfer:, organization:, from_business:)
    @transfer = transfer
    @organization = organization
    @from_business = from_business
  end
end
