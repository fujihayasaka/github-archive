# typed: strict
# frozen_string_literal: true

module Copilot
  class MetricSummary < ApplicationRecord::Copilot
    include ::Instrumentation::Model
    include Copilot::Helpers

    self.table_name = "copilot_metric_summaries"
    self.strict_loading_by_default = true

    belongs_to :owner, polymorphic: true, strict_loading: false

    validates :owner_id, presence: true
    validates :owner_type, presence: true
    validates :start_date, presence: true
    validates :end_date, presence: true
    validates :total_seats, presence: true
    validates :active_seats, presence: true
    validates :inactive_seats, presence: true
    validates :dormant_seats, presence: true

    validate :must_span_week_correctly
    validate :validate_code_suggestion_events
    validate :validate_loc_generated
    validate :validate_commit_counts
    validate :validate_prs_merged
    validate :validate_pr_lead_times

    private

    sig { void }
    def must_span_week_correctly
      # Currently, we only support weekly summaries that start on a Monday and end on a Sunday.
      if !start_date.monday?
        errors.add(:start_date, "must be a Monday")
      end

      if !end_date.sunday?
        errors.add(:end_date, "must be a Sunday")
      end

      if end_date - start_date != 6
        errors.add(:end_date, "must be the following Sunday")
      end
    end

    sig { params(attribute: Symbol, segment: String).void }
    def validate_rate_bucket(attribute, segment)
      bucket = self[attribute]&.dig(segment)
      if bucket.nil?
        errors.add(attribute, "#{segment} is missing")
        return
      end

      unless bucket["total"].is_a?(Numeric)
        errors.add(attribute, "#{segment} has invalid 'total' value type (expected Numeric, got #{bucket["total"].class})")
      end

      unless bucket["accepted"].is_a?(Numeric)
        errors.add(attribute, "#{segment} has invalid 'accepted' value type (expected Numeric, got #{bucket["accepted"].class})")
      end

      unless bucket["acceptance_rate"].is_a?(Float)
        errors.add(attribute, "#{segment} has invalid 'acceptance_rate' value type (expected Float, got #{bucket["acceptance_rate"].class})")
      end

      if bucket["acceptance_rate"].is_a?(Float) && (bucket["acceptance_rate"] < 0.0 || bucket["acceptance_rate"] > 1.0)
        errors.add(attribute, "#{segment} has 'acceptance_rate' value outside allowed range 0.0-1.0")
      end
    end

    sig { params(attribute: Symbol, segment: String).void }
    def validate_averages_bucket(attribute, segment)
      bucket = self[attribute]&.dig(segment)
      if bucket.nil?
        errors.add(attribute, "#{segment} is missing")
        return
      end

      unless bucket["average"].is_a?(Numeric)
        errors.add(attribute, "#{segment} has invalid 'average' value type (expected Numeric, got #{bucket["average"].class})")
      end

      unless bucket["percent_difference"].nil? || bucket["percent_difference"].is_a?(Float)
        errors.add(attribute, "#{segment} has invalid 'percent_difference' value type (expected Float, got #{bucket["percent_difference"].class})")
      end
    end


    sig { void }
    def validate_code_suggestion_events
      return unless code_suggestion_events.present?

      %w[high_engagement moderate_engagement low_engagement].each do |segment|
        validate_rate_bucket(:code_suggestion_events, segment)
      end
    end

    sig { void }
    def validate_loc_generated
      return unless loc_generated.present?

      %w[high_engagement moderate_engagement low_engagement].each do |segment|
        validate_rate_bucket(:loc_generated, segment)
      end
    end

    sig { void }
    def validate_commit_counts
      return unless commit_counts.present?

      %w[high_engagement moderate_engagement low_engagement no_copilot].each do |segment|
        validate_averages_bucket(:commit_counts, segment)
      end
    end

    sig { void }
    def validate_prs_merged
      return unless prs_merged.present?

      %w[high_engagement moderate_engagement low_engagement no_copilot].each do |segment|
        validate_averages_bucket(:prs_merged, segment)
      end
    end

    sig { void }
    def validate_pr_lead_times
      return unless pr_lead_times.present?

      %w[high_engagement moderate_engagement low_engagement no_copilot].each do |segment|
        validate_averages_bucket(:pr_lead_times, segment)
      end
    end
  end
end
