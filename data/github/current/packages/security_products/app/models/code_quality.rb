# typed: strict
# frozen_string_literal: true

# Helper methods on the CodeQuality module
module CodeQuality
  sig { params(repository: Repository, code_quality_enablement: T.nilable(CodeQualityEnablement)).returns(T::Boolean) }
  def self.enabled?(repository, code_quality_enablement: nil)
    available?(repository) && (code_quality_enablement || CodeQualityEnablement.new(repository)).enabled?
  end

  sig { params(repository: Repository, code_quality_enablement: T.nilable(CodeQualityEnablement)).returns(T::Boolean) }
  def self.waiting?(repository, code_quality_enablement: nil)
    available?(repository) && (code_quality_enablement || CodeQualityEnablement.new(repository)).waiting?
  end

  sig { params(entity: T.any(Repository, Business)).returns(T::Boolean) }
  def self.available?(entity)
    if entity.is_a?(Repository)
      FeatureFlag.vexi.enabled?(:code_quality, entity, entity.owner, default: false) &&
      !FeatureFlag.vexi.enabled?(:code_quality_disable, entity, entity.owner, default: false) &&
      !GitHub.enterprise? &&
      entity.owner&.organization? # Code Quality is only available for organizations
    else
      FeatureFlag.vexi.enabled?(:code_quality, entity, default: false) &&
      !FeatureFlag.vexi.enabled?(:code_quality_disable, entity, default: false) &&
      !GitHub.enterprise?
    end
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.recent_activity_enabled?(repository)
    !FeatureFlag.vexi.enabled?(:code_quality_recent_activity_disable, repository, repository.owner, default: false)
  end

  sig { params(rule_severity: T.any(String, Symbol, Integer)).returns(T.any(Integer, Symbol)) }
  def self.get_severity_level_from_rule_severity(rule_severity)
    if rule_severity.is_a?(Integer)
      return rule_severity if AutomatedReviewComment.severities.values.include?(rule_severity)
      return :severity_none
    end

    case rule_severity.to_s
    when "RULE_SEVERITY_NONE"
      :severity_none
    when "RULE_SEVERITY_NOTE"
      :severity_note
    when "RULE_SEVERITY_WARNING"
      :severity_warning
    when "RULE_SEVERITY_ERROR"
      :severity_error
    else
      :severity_none
    end
  end

  sig { returns(T::Hash[String, String]) }
  def self.code_quality_docs_urls
    {
      "about" => DocsUrlConfig.url_for("code-security/about-code-quality"),
      "enable" => DocsUrlConfig.url_for("code-security/enable-code-quality"),
      "improve" => DocsUrlConfig.url_for("code-security/improve-recent-merges"),
      "metrics" => DocsUrlConfig.url_for("code-security/metrics-and-ratings"),
    }
  end
end
