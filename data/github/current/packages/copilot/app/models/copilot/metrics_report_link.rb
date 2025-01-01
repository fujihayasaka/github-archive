# typed: strict
# frozen_string_literal: true

module Copilot
  # Stores download links (array of Azure blob URLs) for the latest 28-day Copilot metrics reports.
  # One row per (business_id, report_type). Updated only when a newer (or same-day) report arrives.
  class MetricsReportLink < ApplicationRecord::Copilot
    include ::Instrumentation::Model
    include Copilot::Helpers

    self.table_name = "copilot_metrics_report_links"
    self.strict_loading_by_default = true

    belongs_to :business, class_name: "::Business"

    REPORT_TYPE_MAP = T.let({
      enterprise_28_day: 1,
      users_28_day: 2,
    }.freeze, T::Hash[Symbol, Integer])

    enum :report_type, REPORT_TYPE_MAP

    DownloadLinksType = T.type_alias { T::Array[String] }

    validates :business_id,
      presence: true,
      numericality: { only_integer: true, greater_than: 0 },
      uniqueness: { scope: :report_type }

    validates :report_type, presence: true  # the enum enforces allowed values; we only need presence here
    validates :report_end_day, presence: true
    validate :validate_report_end_day_is_date
    validates :download_links, presence: true
    validate :validate_download_links_structure

    sig do
      params(
        business_id: Integer,
        report_type: T.any(String, Symbol),
        report_end_day: Date,
        download_links: DownloadLinksType
      ).returns(MetricsReportLink)
    end
    def self.upsert_latest!(business_id:, report_type:, report_end_day:, download_links:)
      sym = report_type.to_sym
      type_value = REPORT_TYPE_MAP[sym]
      raise ArgumentError, "invalid report_type: #{report_type.inspect}" if type_value.nil?

      record = find_or_initialize_by(business_id: business_id, report_type: type_value)

      if record.new_record? || report_end_day >= record.report_end_day
        record.assign_attributes(
          report_end_day: report_end_day,
          download_links: download_links
        )
        record.save!
      end

      record
    end

    private

    sig { void }
    def validate_report_end_day_is_date
      return if report_end_day.is_a?(Date)

      errors.add(:report_end_day, "must be a Date object")
    rescue NoMethodError
      errors.add(:report_end_day, "must be a Date object")
    end

    sig { void }
    def validate_download_links_structure
      # We want to read the raw to validate the actual DB payload without any accessor magic.
      raw = self[:download_links]
      unless raw.is_a?(Array)
        errors.add(:download_links, "must be an Array of URLs")
        return
      end

      if raw.empty?
        errors.add(:download_links, "must contain at least one URL")
        return
      end

      unless raw.all? { |v| v.is_a?(String) && v.present? }
        errors.add(:download_links, "each entry must be a non-empty String URL")
      end
    end
  end
end
