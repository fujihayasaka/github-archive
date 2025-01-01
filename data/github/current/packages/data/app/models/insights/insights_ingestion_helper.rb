# typed: strict
# frozen_string_literal: true

module Insights::InsightsIngestionHelper
  include InsightsHelper

  sig { params(state: String).returns(T::Boolean) }
  def ingestion_allowed?(state)
    [ONBOARDING_STATE, ERROR_READY_STATE, READY_STATE, OFF_STATE].include? state
  end
end
