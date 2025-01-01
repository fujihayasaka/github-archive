# typed: true
# frozen_string_literal: true

class ReachabilityAnalysisStatusUpdate < ApplicationRecord::Notify
  belongs_to :reachability_analysis,
    inverse_of: :status_updates,
    touch: true,
    required: true

  enum :status, {
    other: 0,
    setting_up: 1,
    downloading_packages: 2,
    generating_model: 3,
    analyzing_ghsa: 4,
    uploading_artifact: 5,
    posting_results: 6,
    completed: 7,
    error: 8,
  }

  validates :reachability_analysis, presence: true
end
