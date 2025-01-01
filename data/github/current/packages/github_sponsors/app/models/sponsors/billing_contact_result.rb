# typed: true
# frozen_string_literal: true

module Sponsors
  class BillingContactResult
    def self.success(contact_data)
      new(contact_data, true, nil)
    end

    def self.error(error)
      new(nil, false, error)
    end

    def initialize(contact_data, success, error)
      @contact_data = contact_data
      @error = error
      @success = success
    end

    attr_reader :error, :contact_data

    def success?
      !!@success
    end

    def error?
      !!error
    end
  end
end
