# typed: true
# frozen_string_literal: true

require "react_payload"

class Repos::CodeQuality::RepositoriesController < Repos::CodeQuality::BaseRepositoryController
  include ScanningControllerMethods
  class IndexPayload < ReactPayload::Base
    def route_id
      "repoCodeQualityIndexRoute"
    end

    def initialize(
      owner,
      repo,
      last_scan_at,
      maintainability,
      reliability
    )
      @owner = owner
      @repo = repo
      @last_scan_at = last_scan_at
      @maintainability = maintainability
      @reliability = reliability
    end

    def payload
      {
        owner: @owner,
        repo: @repo,
        lastScanAt: @last_scan_at,
        maintainability: @maintainability,
        reliability: @reliability,
      }
    end
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :check_code_scanning_read

  def index
    # Call the counts endpoint
    response = GitHub::Turboquality.client.counts(Turboquality::Proto::CountsRequest.new(
      repository_id: current_repository.id,
    ))
    raise StandardError.new(response.error.to_s) if response.error.present?

    last_scan_at = response.data.last_scan_at
    maintainability = get_maintanability_count(response.data.counts.to_a)
    reliability = get_reliability_count(response.data.counts.to_a)
    payload = IndexPayload.new(
      current_repository.owner.display_login,
      current_repository.name,
      last_scan_at,
      serialized_count(count: maintainability),
      serialized_count(count: reliability))

    render_react_html(
      title: "Code quality",
      app_name: "code-quality",
      payload:,
      layout: "layouts/code_quality/repositories_sidebar_container",
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
