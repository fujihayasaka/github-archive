# typed: false
# frozen_string_literal: true

class Organization
  class TermsOfServiceAcceptance < ApplicationRecord::Domain::Users
    self.table_name = "organization_terms_of_service_acceptances"

    belongs_to :organization

    validates :organization_id, presence: true

    enum :accepted_terms_type, {
      standard: "Standard",
      custom: "Custom",
      corporate: "Corporate",
      evaluation: "Evaluation",
      esa_education: "ESA+Education"
    }
  end
end
