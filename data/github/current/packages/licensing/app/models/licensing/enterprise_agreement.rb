# typed: true
# frozen_string_literal: true

module Licensing
  class EnterpriseAgreement < ApplicationRecord::Domain::Billing

    include GitHub::Relay::GlobalIdentification
    include GitHub::Validations
    include Instrumentation::Model

    belongs_to :business

    CATEGORIES = [
      ["Visual Studio Bundle", "visual_studio_bundle"],
      ["GitHub Enterprise Unified", "github_enterprise_unified"],
      ["Metered", "metered"]
    ]
    STATUSES = [%w[Active active], %w[Ended ended]]

    enum :category, { visual_studio_bundle: 0, github_enterprise_unified: 1, metered: 2 }
    enum :status, { active: 0, ended: 1 }

    validates :agreement_id, presence: true, uniqueness: { case_sensitive: false }
    validates :business, presence: true
    validates :category, presence: true, inclusion: { in: categories.keys }
    validates :status, presence: true, inclusion: { in: statuses.keys }
    validates :seats, numericality: { equal_to: 0 }, unless: :visual_studio_bundle?

    after_commit :sync_bundled_license_agreement_business, on: [:create, :update]
    after_commit :update_billing_target_in_billing_platform, on: [:create, :update]

    after_create_commit :instrument_creation
    after_update_commit :instrument_update
    after_destroy_commit :instrument_destroy

    scope :is_active, -> { where("ends_at IS NULL OR ends_at > NOW()") }

    def agreement_id=(value)
      super(value.to_s.strip.presence)
    end

    private

    sig { void }
    def instrument_creation
      business&.instrument :enterprise_agreement_create, event_payload
    end

    sig { void }
    def instrument_update
      business&.instrument :enterprise_agreement_update, event_payload
    end

    sig { void }
    def instrument_destroy
      business&.instrument :enterprise_agreement_destroy, event_payload
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def event_payload
      {
        agreement_id: agreement_id,
        category: category,
        status: status,
        seats: seats,
      }
    end

    # Queue Licensing::BundledLicenseAssignmentBusinessLinkingJob
    # Updates related Licensing:BundledLicenseAssignment business
    # to match the Licensing::EnterpriseAgreement business
    def sync_bundled_license_agreement_business
      Licensing::BundledLicenseAssignmentBusinessLinkingJob.perform_later(self)
    end

    def update_billing_target_in_billing_platform
      GitHub.dogstats.increment("billing_enterprise_agreement.billing_platform_update_customer")
      customer = business&.customer

      unless customer.nil?
        Billing::UpdateCustomerInBillingPlatformJob.perform_later(customer)
        GitHub.dogstats.increment("billing_enterprise_agreement.billing_platform_update_customer_called")
      end
    end
  end
end
