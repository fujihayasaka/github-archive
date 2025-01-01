# typed: true
# frozen_string_literal: true

class SponsorsActivityMetric < ApplicationRecord::Domain::Sponsors
  enum :metric, [:subscription_value]

  belongs_to :sponsorable, class_name: "User", inverse_of: :sponsors_activity_metrics

  scope :most_recent, -> (as_of:) { where("recorded_on <= ?", as_of.to_date).order(recorded_on: :desc).limit(1) }
  scope :on, -> (date) { where(recorded_on: date.to_date) }
end
