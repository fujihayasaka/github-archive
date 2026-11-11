require "turboquality_pb"
require "turboquality_twirp"
require "coverage_pb"
require "coverage_twirp"
require "coverage_quality_gates_pb"
require "coverage_quality_gates_twirp"
require "code_quality_agent_pb"
require "code_quality_agent_twirp"

module Turboquality
  CodeQualityAPI = Turboquality::Proto::CodeQualityAPIClient
  CoverageAgent = Turboquality::Proto::CoverageAgentClient
  CoverageQualityGates = Turboquality::Proto::CoverageQualityGatesClient
  CodeQualityAgent = Turboquality::Proto::CodeQualityAgentClient
end
