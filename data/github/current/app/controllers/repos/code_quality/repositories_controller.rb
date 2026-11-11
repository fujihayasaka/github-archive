# typed: true
# frozen_string_literal: true

require "react_payload"

class Repos::CodeQuality::RepositoriesController < Repos::CodeQuality::BaseRepositoryController
  class IndexPayload < ReactPayload::Base
    def route_id
      "repoCodeQualityIndexRoute"
    end

    sig do
      params(
        owner: String,
        repo: String,
        branch: String,
        last_scan_at: T.nilable(T.any(String, Google::Protobuf::Timestamp)),
        maintainability: T::Hash[Symbol, T.untyped],
        reliability: T::Hash[Symbol, T.untyped],
        recent_activity_enabled: T::Boolean,
        recent_suggestions_count: T.nilable(Integer),
        code_quality_docs_urls: T::Hash[String, String],
        enabled: T::Boolean,
        readonly: T::Boolean,
        blocked_by_policy: T::Boolean,
        new_design_enabled: T::Boolean
      ).void
    end
    def initialize(
      owner:,
      repo:,
      branch:,
      last_scan_at:,
      maintainability:,
      reliability:,
      recent_activity_enabled:,
      recent_suggestions_count:,
      code_quality_docs_urls:,
      enabled:,
      readonly:,
      blocked_by_policy:,
      new_design_enabled:
    )
      @owner = owner
      @repo = repo
      @branch = branch
      @last_scan_at = last_scan_at
      @maintainability = maintainability
      @reliability = reliability
      @recent_activity_enabled = recent_activity_enabled
      @recent_suggestions_count = recent_suggestions_count
      @code_quality_docs_urls = code_quality_docs_urls
      @readonly = readonly
      @enabled = enabled
      @blocked_by_policy = blocked_by_policy
      @new_design_enabled = new_design_enabled
    end

    def payload
      {
        owner: @owner,
        repo: @repo,
        branch: @branch,
        lastScanAt: @last_scan_at,
        maintainability: @maintainability,
        reliability: @reliability,
        recentActivityEnabled: @recent_activity_enabled,
        recentSuggestionsCount: @recent_suggestions_count,
        codeQualityDocsUrls: @code_quality_docs_urls,
        readonly: @readonly,
        enabled: @enabled,
        blockedByPolicy: @blocked_by_policy,
        newDesignEnabled: @new_design_enabled,
      }
    end
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :check_code_quality_read

  def index
    # Call the counts endpoint
    counts_response = GitHub::Turboquality.client.counts(Turboquality::Proto::CountsRequest.new(
      repository_id: current_repository.id,
    ))
    raise StandardError.new(counts_response.error.to_s) if counts_response.error.present?

    if CodeQuality.recent_activity_enabled?(current_repository)
      recent_suggestions_count = counts_response.data.ai_findings_count
    end

    last_scan_at = counts_response.data.last_scan_at
    maintainability = get_maintanability_count(counts_response.data.counts.to_a)
    reliability = get_reliability_count(counts_response.data.counts.to_a)
    payload = IndexPayload.new(
      owner: current_repository.owner.display_login,
      repo: current_repository.name,
      branch: current_repository.default_branch,
      last_scan_at:,
      maintainability: serialized_count(count: maintainability),
      reliability: serialized_count(count: reliability),
      recent_activity_enabled: CodeQuality.recent_activity_enabled?(current_repository),
      recent_suggestions_count:,
      code_quality_docs_urls: CodeQuality.code_quality_docs_urls,
      enabled: CodeQuality.enabled?(current_repository),
      readonly: code_quality_readable? && !code_quality_writable?,
      blocked_by_policy: CodeQualityEnablement.policy_check(repository: current_repository, current_user: current_user).value == false,
      new_design_enabled: true,
    )

    respond_with_react(
      title: "Code quality · Standard findings · #{current_repository.name_with_display_owner}",
      app_name: "code-quality",
      payload:,
      layout: "layouts/code_quality/repositories_sidebar_container",
      page_data: {
        selected_tab: CodeQuality.recent_activity_enabled?(current_repository) ? :code_quality_findings : :code_quality
      }
    )
  end

  private

  sig { params(counts: T::Array[Turboquality::Proto::ResultCount]).returns(Turboquality::Proto::ResultCount) }
  def get_maintanability_count(counts)
    maintainability_counts = counts.filter { |count| count.category == :CAT_MAINTAINABILITY }
    raise StandardError.new("Expected a maximum of one maintainability count, but got #{maintainability_counts.length}") if maintainability_counts.length > 1

    # Create empty maintainability count if none exists
    maintainability_counts = [Turboquality::Proto::ResultCount.new(
      category: :CAT_MAINTAINABILITY,
      grade: :GRADE_A,
      count: 0
    )] if maintainability_counts.empty?

    T.must(maintainability_counts.first)
  end

  sig { params(counts: T::Array[Turboquality::Proto::ResultCount]).returns(Turboquality::Proto::ResultCount) }
  def get_reliability_count(counts)
    reliability_counts = counts.filter { |count| count.category == :CAT_RELIABILITY }
    raise StandardError.new("Expected a maximum of one reliability count, but got #{reliability_counts.length}") if reliability_counts.length > 1

    # Create empty reliability count if none exists
    reliability_counts = [Turboquality::Proto::ResultCount.new(
      category: :CAT_RELIABILITY,
      grade: :GRADE_A,
      count: 0
    )] if reliability_counts.empty?

    T.must(reliability_counts.first)
  end

  sig { params(count: Turboquality::Proto::ResultCount).returns(T::Hash[Symbol, T.untyped]) }
  def serialized_count(count:)
    findings_count = count.count
    grade = count.grade

    {
      grade: serilized_grade(grade:),
      findingsCount: findings_count
    }
  end

  sig { params(grade: Object).returns(T.untyped) }
  def serilized_grade(grade:)
    case grade
    when :GRADE_A
      "A"
    when :GRADE_B
      "B"
    when :GRADE_C
      "C"
    when :GRADE_D
      "D"
    else
      raise ArgumentError, "Unknown grade: #{grade}" if grade.is_a?(Integer)
    end
  end
end
