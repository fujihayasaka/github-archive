# frozen_string_literal: true

class GHSLRequest < ApplicationRecord
  belongs_to :cve_review, primary_key: "ghsa_id", foreign_key: "ghsa_id", inverse_of: :ghsl_request

  validates :ghsa_id, ghsa_id: true, presence: true
  validates :ghsl_id, length: { minimum: 0 }
  validates :ghsl_issue, length: { minimum: 0 }
end
