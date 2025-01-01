# typed: strict
# frozen_string_literal: true

# Helper methods on the CodeQuality module
module CodeQuality
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.enabled?(repository)
    available?(repository) && CodeQualityEnablement.new(repository).enabled?
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.available?(repository)
    (repository.feature_flag_enabled?(:code_quality, default: false) || !!repository.owner&.feature_flag_enabled?(:code_quality, default: false)) &&
    !GitHub.enterprise? &&
    repository.owner&.organization? # Code Quality is only available for organizations
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.automated_review_comment_enabled?(repository)
    !!(repository.feature_flag_enabled?(:code_quality_automated_review_comment, default: false) || repository.owner&.feature_flag_enabled?(:code_quality_automated_review_comment, default: false))
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.recent_activity_enabled?(repository)
    !!(repository.feature_flag_enabled?(:code_quality_recent_activity, default: false) || repository.owner&.feature_flag_enabled?(:code_quality_recent_activity, default: false))
  end
end
