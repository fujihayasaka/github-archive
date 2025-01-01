# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  class SendEmailToEloquaJob < BillingJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    def perform(uri:, email:)
      Net::HTTP.post_form(URI(uri), "emailAddress" => email)
    end
  end
end
