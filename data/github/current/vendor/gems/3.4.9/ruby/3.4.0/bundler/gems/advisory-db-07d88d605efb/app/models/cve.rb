# frozen_string_literal: true

class CVE < ApplicationRecord
  belongs_to :assigner, optional: true, class_name: "User"
  belongs_to :cve_review, optional: true, primary_key: :assigned_cve_id, foreign_key: :cve_id, inverse_of: :cve

  validates :cve_id, presence: true, uniqueness: true, cve_id: true
  validates :year, presence: true
  validate :year_matches_cve_id
  def year_matches_cve_id
    if cve_id && year && cve_id.slice(AdvisoryDBToolkit::CVEIDValidator::PATTERN, :year) != year.to_s
      errors.add(:year, "must match the CVE ID")
    end
  end

  scope :available, -> { where(assigned_at: nil) }
  scope :by_year, ->(year) { where(year: year) if year.present? }

  def self.first_available_cve_id_for_year(year)
    CVE.transaction do
      record = available.where(year: year).order(:cve_id).lock.first
      next nil unless record

      record.update!(assigned_at: Time.zone.now)
      record.cve_id
    end
  end
end
