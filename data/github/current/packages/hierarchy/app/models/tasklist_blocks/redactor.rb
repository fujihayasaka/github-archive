# typed: true
# frozen_string_literal: true

module TasklistBlocks
  class Redactor
    extend T::Sig
    include GitHub::Tracing

    sig do
      params(
        viewer: T.nilable(::User),
        issues: T::Array[TasklistBlocks::Issue],
        cap_filter: T.untyped,
        options: T::Hash[Symbol, T::Boolean]
      ).void
    end
    def initialize(viewer:, issues:, cap_filter: nil, options: {})
      @viewer = viewer
      @unredacted_issues = issues
      @cap_filter = cap_filter

      @exclude_redacted_issues = options[:exclude_redacted_issues] || false
    end


    sig { returns(T::Array[T.any(TasklistBlocks::Issue, TasklistBlocks::RedactedIssue)]) }
    def issues
      return @issues if defined?(@issues)

      @issues = @unredacted_issues.filter_map do |issue|
        next if hidden_from_user_issue_ids.include?(issue.issue_id)

        if issue.draft?
          issue
        elsif visible_issue_ids.include?(issue.issue_id) && !cap_unauthorized_owner_ids.include?(issue.owner_id)
          issue
        else
          next if @exclude_redacted_issues
          TasklistBlocks::RedactedIssue.new(
            position: issue.position,
            title: issue.original_text || issue.url,
          )
        end
      end
    end
    trace_method(:issues)

    private

    sig { params(issue: IssuesGraph::Proto::Issue).returns(T::Boolean) }
    def draft_issue?(issue)
      is_draft_item_type = issue.itemType.nil? || @item_type == :UNDEFINED || issue.itemType == TrackingBlocks::DraftIssue::ITEM_TYPE.to_sym
      is_draft_state = [TasklistBlocks::DraftIssueState::OPEN, TasklistBlocks::DraftIssueState::CLOSED].include?(issue.state)
      is_draft_item_type && is_draft_state
    end

    sig { returns(T.any(Array, ActiveRecord::Relation)) }
    def visible_issues
      return @visible_issues if defined?(@visible_issues)

      authorizables = Set.new
      @unredacted_issues.each do |issue|
        unless issue.draft?
          authorizables << issue.to_authorizable
        end
      end

      @visible_issues = if authorizables.any?
        ::Issue.visible_for(viewer: @viewer, authorizables: authorizables)
      else
        []
      end
    end

    sig { returns(T::Array[Integer]) }
    def visible_issue_ids
      @visible_issue_ids ||= visible_issues.collect(&:id)
    end

    sig { returns(T::Array[::Issue]) }
    def hidden_from_user_issues
      Promise.all(
        visible_issues.map do |issue|
          issue.async_hide_from_user?(@viewer).then do |hidden|
            issue if hidden
          end
        end
      ).sync.compact
    end

    sig { returns(T::Array[Integer]) }
    def hidden_from_user_issue_ids
      @hidden_from_user_issue_ids ||= hidden_from_user_issues.collect(&:id)
    end

    sig { returns(T::Set[T.any(Integer, String)]) }
    def owner_ids
      return @owner_ids if defined?(@owner_ids)
      owner_ids = Set.new
      @unredacted_issues.each do |issue|
        unless issue.draft?
          owner_ids << issue.owner_id
        end
      end

      @owner_ids = owner_ids
    end

    sig { returns(T::Array[Integer]) }
    def cap_unauthorized_owner_ids
      @cap_unauthorized_owner_ids ||= if @cap_filter.present? && owner_ids.any?
        owners = User.where(id: owner_ids)
        @cap_filter.unauthorized_resources(owners).collect(&:id)
      else
        []
      end
    end
  end
end
