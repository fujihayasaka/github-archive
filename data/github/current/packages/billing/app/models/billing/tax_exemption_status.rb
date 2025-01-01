# typed: strict
# frozen_string_literal: true

class Billing::TaxExemptionStatus < ApplicationRecord::Domain::Billing
  include Instrumentation::Model

  belongs_to :customer

  enum :status, { approved: 0, rejected: 1 }

  after_commit :sync_to_zuora, if: :status_needs_updating?
  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update

  # Note, when we reject a certificate, we notify the customer (via email) with this reason.
  validates :status_reason, length: { maximum: 255 }
  validates_presence_of :status_reason, if: :rejecting?

  # The display_certificate_filename method is used in the view to display the name of the certificate file.
  # We use this name to avoid exposing our "internal" file name (certificate_name) to the user.
  sig { returns(String) }
  def display_certificate_filename
    return "N/A" unless certificate_name.present?

    file_extension = File.extname(certificate_name)
    login = account.display_login

    "#{login}-salestax-exemption#{file_extension}"
  end

  sig { returns(Billing::Types::OrgOrBusiness) }
  def account
    customer = T.must(self.customer)
    return T.must(customer.business) if customer.business.present?

    customer.organizations.sole
  end

  private

  delegate :zuora_account_id, to: :customer

  sig { returns(T::Boolean) }
  def rejecting?
    return false unless rejected?

    status_reason.blank?
  end

  sig { returns(T::Boolean) }
  def status_needs_updating?
    # The id_previously_changed? check is necessary in order to trigger a sync upon the initial creation of a TaxExemptionStatus
    id_previously_changed? || previous_changes[:status].present?
  end

  sig { void }
  def sync_to_zuora
    return unless zuora_account_id.present?
    SyncZuoraTaxExemptStatusJob.perform_later(zuora_account_id: zuora_account_id, tax_exemption_status_id: self.id)
  end

  sig { void }
  def instrument_create
    instrument :tax_exemption_status_created
  end

  sig { void }
  def instrument_update
    instrument :tax_exemption_status_updated
  end

  sig { returns(Symbol) }
  def event_prefix
    :billing
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    {
      customer_id: customer_id,
      certificate_name_was: certificate_name_previously_was,
      certificate_name: certificate_name,
      status: status,
      zuora_account_id: zuora_account_id
    }.tap do |payload|
      payload[account.event_prefix] = account
    end
  end
end
