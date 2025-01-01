# typed: true
# frozen_string_literal: true

class Stafftools::Billing::BillingEmailRecipientsListComponent < ApplicationComponent

  attr_reader :primary_email, :external_emails

  def initialize(primary_email: nil, external_emails: [])
    @primary_email = primary_email
    @external_emails = external_emails
  end
end
