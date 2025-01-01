# typed: true
# frozen_string_literal: true

# rubocop:disable Rails/ModuleNaming
class CVEEPSS < ApplicationRecord::Notify
  self.table_name = "cve_epss"

  validates :cve_id, presence: true, length: { maximum: 20 }, uniqueness: true
  validates :percentage, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :percentile, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :calculation_date, presence: true

  belongs_to :vulnerability, class_name: "Vulnerability", foreign_key: :cve_id, primary_key: :cve_id, inverse_of: :cve_epss

  def percentage=(value)
    write_attribute(:percentage, value.to_f) if value.present?
  end

  def percentile=(value)
    write_attribute(:percentile, value.to_f) if value.present?
  end
end
# rubocop:disable Rails/ModuleNaming
