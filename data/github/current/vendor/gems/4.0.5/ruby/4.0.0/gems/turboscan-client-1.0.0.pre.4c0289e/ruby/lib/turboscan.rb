# frozen_string_literal: true

require "turboscan/proto/results_twirp"
require "turboscan/proto/managed_analyses_twirp"
require "turboscan/proto/insights_twirp"
require "turboscan/proto/suggested_fixes_twirp"
require "turboscan/proto/turboscan_twirp"
require "turboscan/proto/risk_assessment_twirp"
require "turboscan/proto/stafftools_twirp"
require "turboscan/workflow"
require "turboscan/suggested_fix"

module Turboscan
  ManagedAnalysesClient = Turboscan::Proto::ManagedAnalysesClient
  SuggestedFixesClient = Turboscan::Proto::SuggestedFixesClient
  RiskAssessmentClient = Turboscan::Proto::RiskAssessmentClient
  StafftoolsClient = Turboscan::Proto::StafftoolsClient
  ResultsClient = Turboscan::Proto::ResultsClient
end
