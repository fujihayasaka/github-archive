# typed: strict
# frozen_string_literal: true

module HierarchyCommands
  # When we are about to render an issue, check to see if the data that the HTML
  # pipeline has about tasklists matches the data we have received from the
  # Issues Graph service. If the data is out of sync, log and stat so that we
  # can understand the frequency and nature of the mismatches. Otherwise, stat
  # success.
  #
  # TLB = TasklistBlock
  # TLI = TasklistItem
  #
  # In short the algorithm is:
  # 1. If the issue does not contain tasklists, stat success.
  # 2. If the issue contains tasklists, but the Issues Graph service does not
  #   have any data about tasklists, log and stat that we are missing data.
  # 3. If the issue contains tasklists and the Issues Graph service has data
  #  about tasklists, but the data is out of sync, log and stat that we have
  #  mismatched data.
  # 4. If the issue contains tasklists and the Issues Graph service has data
  #  about tasklists and the data is in sync, stat success.
  class CheckDatabaseSync
    STATS_KEY_SYNCED = "hierarchy_commands.check_database_sync.sync_check"
    PRECACHE = "precache"
    MD_AT_REST = "md-at-rest"
    LOG_MESSAGE = "issue hierarchy not synced"
    HIERARCHY_NOT_PRELOADED = "hierarchy_not_preloaded"
    MISSING_DATA = "missing_data"
    MISMATCHED_TLB_COUNT = "mismatched_tlb_count"
    MISMATCHED_TLI_COUNT = "mismatched_tli_count"
    MISMATCHED_TLI_DATA = "mismatched_tli_data"
    NO_TASKLISTS = "no_tasklists"
    DATA_IN_SYNC = "data_in_sync"

    sig do
      params(
        issue: Issue,
        repository: Repository,
        viewer: T.nilable(User),
      ).void
    end
    def initialize(issue:, repository:, viewer: nil)
      @issue = T.let(issue, Issue)
      @repository = T.let(repository, Repository)
      @viewer = T.let(viewer, T.nilable(User))
      @error_reason = T.let(nil, T.nilable(String))
    end

    sig { returns(String) }
    def pipeline_strategy
      GitHub.flipper[:tasklist_block_precache].enabled?(@repository.owner) ? PRECACHE : MD_AT_REST
    end

    sig { returns(Result) }
    def call
      return build_success unless GitHub.flipper[:tasklist_block_sync_check].enabled?(@viewer)

      result = check_for_sync_error
      if result.success?
        GitHub.dogstats.increment(
          STATS_KEY_SYNCED,
          tags: [
            "synced:true",
            "pipeline_strategy:#{pipeline_strategy}",
            "outcome:#{result.message}",
          ]
        )
      else
        GitHub.logger.error(
          LOG_MESSAGE,
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.catalog_service": "github/issues-graph",
          "gh.repository_id": @repository.id,
          "gh.issue_id": @issue.id,
          "gh.issues_graph.pipeline_strategy": pipeline_strategy,
          "gh.user_id": @viewer&.id,
          "gh.issues_graph.sync_error": result.message,
        )
        GitHub.dogstats.increment(
          STATS_KEY_SYNCED,
          tags: [
            "synced:false",
            "pipeline_strategy:#{pipeline_strategy}",
            "sync_error:#{result.message}",
          ]
        )
      end

      result
    end

    sig { returns(Result) }
    private def check_for_sync_error
      return build_success(NO_TASKLISTS) unless contains_tasklists?
      return build_error(HIERARCHY_NOT_PRELOADED) unless hierarchy_present?
      return build_error(build_missing_data_message) unless both_are_present?
      return build_error(MISMATCHED_TLB_COUNT) unless pipeline_tlbs.count == T.must(issues_graph_tlbs).count

      pipeline_tlbs.each.with_index do |tlb, index|
        break if @error_reason
        return build_error(MISMATCHED_TLB_COUNT) unless ig_tlb = T.must(issues_graph_tlbs)[index]
        return build_error(MISMATCHED_TLI_COUNT) unless tlb.items.count == ig_tlb.items.count

        tlb.items.each.with_index do |item, item_index|
          unless items_match?(item, ig_tlb.items[item_index])
            @error_reason = MISMATCHED_TLI_DATA
            break
          end
        end
      end

      @error_reason ? build_error(@error_reason) : build_success(DATA_IN_SYNC)
    end

    sig { params(error: String).returns(Result) }
    private def build_error(error)
      @error_reason = error
      Result.new(
        success: false,
        message: error,
      )
    end

    sig { params(message: T.nilable(String)).returns(Result) }
    private def build_success(message = nil)
      Result.new(
        success: true,
        message: message || "not_specified",
      )
    end

    sig { returns(String) }
    private def build_missing_data_message
      extension = pipeline_tlbs.present? ? "_issues_graph" : "_pipeline"
      MISSING_DATA + extension
    end

    sig do
      params(
        item: T.any(TasklistBlocks::IssueReference, TrackingBlocks::DraftIssue),
        ig_item: T.nilable(TasklistBlocks::Issue),
      ).returns(T::Boolean)
    end
    private def items_match?(item, ig_item)
      return false unless ig_item

      if item.is_a?(TrackingBlocks::DraftIssue)
        state_matches?(item, ig_item) &&
          item.draft_issue == ig_item.title &&
          ig_item.item_type&.to_s == TrackingBlocks::DraftIssue::ITEM_TYPE
      else
        item.issue.url == ig_item.url && item.issue.state == ig_item.state
      end
    end

    sig do
      params(
        item: TrackingBlocks::DraftIssue,
        ig_item: TasklistBlocks::Issue
      ).returns(T::Boolean)
    end
    private def state_matches?(item, ig_item)
      if item.closed
        ig_item.state == TasklistBlocks::DraftIssueState::CLOSED
      else
        ig_item.state == TasklistBlocks::DraftIssueState::OPEN
      end
    end

    sig do
      returns(T::Array[TasklistBlocks::TasklistBlock])
    end
    private def pipeline_tlbs
      result = @issue.body_result&.tasklist_blocks
      return result.values if result&.is_a?(Hash) # precache makes this a hash

      result || []
    end

    sig { returns(T.nilable(T::Array[TasklistBlock])) }
    private def issues_graph_tlbs
      @issue.preload_hierarchy(viewer: @viewer) unless @issue.hierarchy_loaded?
      maybe_log_preload_oof

      @issue.hierarchy&.tasklist_blocks
    end

    sig { returns(T::Boolean) }
    private def hierarchy_present?
      @issue.hierarchy.present?
    end

    sig { void }
    private def maybe_log_preload_oof
      return if hierarchy_present?

      GitHub.logger.info(
        "Preload failed for issues-graph sync check",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.catalog_service": "github/issues-graph",
        "gh.repository_id": @repository.id,
        "gh.issue_id": @issue.id,
        "gh.issues_graph.pipeline_strategy": pipeline_strategy,
        "gh.user_id": @viewer&.id,
      )
    end

    sig { returns(T::Boolean) }
    private def contains_tasklists?
      pipeline_tlbs.present? || issues_graph_tlbs.present?
    end

    sig { returns(T::Boolean) }
    private def both_are_present?
      pipeline_tlbs.present? && issues_graph_tlbs.present?
    end
  end
end
