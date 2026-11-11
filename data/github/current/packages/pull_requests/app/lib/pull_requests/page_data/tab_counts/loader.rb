# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::TabCounts
  class Loader
    include GitHub::ResilienceMixin

    CHANGED_FILES_COUNT_FALLBACK = 0
    CHECKS_COUNT_FALLBACK = 0

    sig { returns(PullRequest) }
    attr_reader :pull_request

    ANNOTATIONS_COUNT_FALLBACK = 0

    class TabCountsData < T::Struct
      const :check_suites_count, Integer
      const :files_changed_count, Integer
      const :conversation_count, Numeric
      const :files_changed_count_limit_exceeded, T::Boolean
      const :annotations_count, Integer
      const :unresolved_conversation_count, Integer
      const :findings_count, Integer
    end

    sig { params(pull_request: PullRequest, limit_config: PullRequests::PageData::Files::PageLimitConfig, current_user: T.nilable(User)).returns(TabCountsData) }
    def self.load(pull_request:, limit_config:, current_user: nil)
      tab_counts = new(pull_request:, limit_config:, current_user:)
      tab_counts.load
    end

    sig { params(pull_request: PullRequest, limit_config: PullRequests::PageData::Files::PageLimitConfig, current_user: T.nilable(User)).void }
    def initialize(pull_request:, limit_config:, current_user: nil)
      @pull_request = pull_request
      @limit_config = limit_config
      @current_user = current_user
    end

    sig { returns(TabCountsData) }
    def load
      TabCountsData.new(
        check_suites_count: checks_count,
        conversation_count: @pull_request.total_comments,
        files_changed_count: files_changed_count,
        files_changed_count_limit_exceeded: @limit_config.files_changed_count_limit_exceeded?,
        annotations_count: annotations_count,
        unresolved_conversation_count: unresolved_conversation_count,
        findings_count: findings_count,
      )
    end

    private

    sig { returns(Integer) }
    def checks_count
      with_database_error_fallback(fallback: CHECKS_COUNT_FALLBACK) do
        @pull_request.latest_check_runs_count
      end
    end

    sig { returns(Integer) }
    def files_changed_count
      changed_files_count = CHANGED_FILES_COUNT_FALLBACK
      begin
        changed_files_count = summary_diff.changed_files
      rescue GitRPC::Error => error
        Failbot.report error
      end

      @limit_config.apply_files_changed_count_limit do
        changed_files_count
      end
    end

    sig { returns(Integer) }
    def annotations_count
      return ANNOTATIONS_COUNT_FALLBACK unless updated_pull_request_header_enabled?

      repository = @pull_request.repository
      return ANNOTATIONS_COUNT_FALLBACK unless repository

      filepaths = changed_filepaths
      return ANNOTATIONS_COUNT_FALLBACK if filepaths.empty?

      with_database_error_fallback(fallback: ANNOTATIONS_COUNT_FALLBACK) do
        annotations = if FeatureFlag.vexi.enabled?(:prs_load_all_alerts, @current_user, default: false)
          @limit_config.apply_paginated_max_limit(
            PullRequests::PageData::Files::PageLimitConfig::LimitType::Annotations
          ) do |limit|
            repository.annotations_for(
              sha: @pull_request.head_sha,
              filenames: filepaths,
              limit: limit,
              inline_only: true,
            )
          end
        else
          @limit_config.apply_page_limit(
            PullRequests::PageData::Files::PageLimitConfig::LimitType::Annotations
          ) do |limit|
            repository.annotations_for(
              sha: @pull_request.head_sha,
              filenames: filepaths,
              limit: limit,
              inline_only: true,
            )
          end
        end
        annotations.to_a.size
      end
    end

    sig { returns(GitHub::Diff) }
    def summary_diff
      @summary_diff ||= T.let(
        @pull_request.historical_comparison.async_diff(summary: true).sync,
        T.nilable(GitHub::Diff),
      )
    end

    sig { returns(T::Array[String]) }
    def changed_filepaths
      summary_diff.deltas.map(&:path)
    rescue GitRPC::Error
      []
    end

    sig { returns(Integer) }
    def unresolved_conversation_count
      return 0 unless updated_pull_request_header_enabled?

      with_database_error_fallback(fallback: 0) do
        threads = @limit_config.apply_paginated_max_limit(
          PullRequests::PageData::Files::PageLimitConfig::LimitType::ReviewThreads
        ) do |limit|
          @pull_request.review_threads.visible_to(@current_user)
            .select(:id, :resolver_id)
            .limit(limit)
        end
        threads.to_a.count { |thread| !thread.resolved? }
      end
    end

    sig { returns(Integer) }
    def findings_count
      return 0 unless FeatureFlag.vexi.enabled?(:copilot_code_review_findings_ui, @current_user, default: false)

      PullRequests::Copilot::FindingsCountCache.count_for(@pull_request, user: @current_user)
    end

    sig { returns(T::Boolean) }
    def updated_pull_request_header_enabled?
      FeatureFlag.vexi.enabled?(:updated_pull_request_header, @pull_request.repository, default: false)
    end
  end
end
