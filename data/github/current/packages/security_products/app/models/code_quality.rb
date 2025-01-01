# typed: strict
# frozen_string_literal: true

# Helper methods on the CodeQuality module
module CodeQuality
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.enabled?(repository)
    (repository.feature_enabled?(:code_quality) || repository.owner&.feature_enabled?(:code_quality)) &&
    !GitHub.enterprise?
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.ingestion_enabled?(repository)
    CodeQuality.enabled?(repository) &&
    !!(repository.feature_enabled?(:code_quality_sarif_ingest) || repository.owner&.feature_enabled?(:code_quality_sarif_ingest))
  end
end
