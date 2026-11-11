# typed: strict
# frozen_string_literal: true

module CodeCoverage
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.available?(repository)
    CodeQuality.available?(repository) &&
      !FeatureFlag.vexi.enabled?(:disable_code_coverage, repository, repository.owner, default: false)
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.workflow_configuration_enabled?(repository)
    available?(repository) && FeatureFlag.vexi.enabled?(:"code-coverage-enablement", repository, repository.owner, default: false)
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.coverage_agent_enabled?(repository)
    available?(repository) && FeatureFlag.vexi.enabled?(:"code-coverage-enablement-cocoa", repository, repository.owner, default: false)
  end
end
