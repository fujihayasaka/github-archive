# typed: true
# frozen_string_literal: true

module Billing
  class PrepaidMeteredUsageRefillCreator
    def initialize(attributes)
      @attributes = attributes
    end

    def create
      record = Billing::PrepaidMeteredUsageRefill.new(attributes)

      result = record.save

      { success: result, record: record }
    end

    def create!
      record = Billing::PrepaidMeteredUsageRefill.new(attributes)

      record.save!

      { success: true, record: record }
    end

    private

    attr_reader :attributes
  end
end
