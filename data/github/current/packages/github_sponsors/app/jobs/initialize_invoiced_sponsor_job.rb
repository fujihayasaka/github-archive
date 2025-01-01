# typed: true
# frozen_string_literal: true

class InitializeInvoicedSponsorJob < ApplicationJob
  extend T::Sig

  include GitHub::Billing::ZuoraRateLimitHandler

  class SelfServeInvoicedSponsorSetupError < StandardError; end

  retry_on_dirty_exit
  queue_as :billing

  # Hash lock to prevent multiple jobs for the same org being enqueued concurrently
  locked_by timeout: 1.hour, key: ->(job) {
    org = job.arguments[0][:org]
    org.id
  }

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, InitializeInvoicedSponsorJob)
    zuora_rate_limit_handler(self, error)
  end

  # :org - the Organization switching to invoicing.
  # :name - String. The customer's full name or business name.
  # :email - String. The customer's email address.
  # :address - a Hash with any subset of the following keys, see
  #            https://stripe.com/docs/api/customers/create#create_customer-address
  #    :city - String. City, district, suburb, town, or village.
  #    :country - String. Two-letter country code https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
  #    :line1 - String. Address line 1.
  #    :line2 - String. Address line 2.
  #    :postal_code - String. Zip or Postal Code.
  #    :state - String. State, county, province, or region.
  sig do
    params(
      org: Organization,
      name: String,
      email: String,
      address: Sponsors::InvoicedSponsorAccountCreator::AddressHash,
      actor: T.nilable(User)
    ).void
  end
  def perform(org:, name:, email:, address:, actor: nil)
    return unless GitHub.sponsors_enabled?

    Failbot.push(
      app: "github-sponsors",
      "gh.actor.id": actor&.id,
      "gh.organization.id": org.id,
      "organization_id": org.id
    )

    creator = Sponsors::InvoicedSponsorAccountCreator.new(
      org: org,
      name: name,
      email: email,
      address: address,
      actor: actor,
    )

    if with_write { creator.setup }
      send_success_email(org: org)
    else
      send_failure_email(org: org)
      Failbot.report(SelfServeInvoicedSponsorSetupError.new(
        "Failed to set up invoiced sponsors account: #{creator.errors.full_messages}"
      ))
    end

    with_write do
      org.clear_active_sponsors_invoice_migration_lock
    end
  end

  private

  sig { params(org: Organization).void }
  def send_failure_email(org:)
    SponsorsPrimerMailer.invoiced_sponsors_setup_failure(org: org).deliver_later
  end

  sig { params(org: Organization).void }
  def send_success_email(org:)
    SponsorsPrimerMailer.invoiced_sponsors_setup_success(org: org).deliver_later
  end
end
