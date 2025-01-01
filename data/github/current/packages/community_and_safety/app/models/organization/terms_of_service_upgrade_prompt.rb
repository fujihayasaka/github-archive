# typed: false
# frozen_string_literal: true

class Organization
  class TermsOfServiceUpgradePrompt < ApplicationRecord::Domain::Users
    self.table_name = "organization_terms_of_service_upgrade_prompts"

    belongs_to :organization

    enum :upgraded_terms_type, {
      corporate: "Corporate",
      esa_education: "ESA+Education"
    }

    validates :organization_id, presence: true
    validates :upgraded_terms_type, presence: true
  end
end
