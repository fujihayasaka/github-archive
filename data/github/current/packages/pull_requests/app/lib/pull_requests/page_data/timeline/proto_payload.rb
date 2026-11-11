# typed: strict
# frozen_string_literal: true

require "github/protobuf/wrappers"
require "pull_requests/v1/timeline_pb"

module PullRequests::PageData::Timeline
  # Converts `TimelineEvents::Loader::Event` structs into the
  # `github.pull_requests.v1.TimelineResponse` proto rendered by
  # `SharedController#timeline`.
  #
  # Consumes the same loader output as `TimelineEvents::Payload` (not its built
  # JSON payload) to avoid shaping the data twice. Fields outside the github-ui
  # `TimelinePayload` contract (`requestedReviewer`, `requestedReviewerTeams`,
  # `reviewedCommitOid`) are intentionally not mapped.
  class ProtoPayload
    Proto = Github::PullRequests::V1
    Event = PullRequests::PageData::TimelineEvents::Loader::Event
    EventUser = PullRequests::PageData::TimelineEvents::Loader::User

    # Maps the loader's `type` discriminant string onto the `TimelineItemType`
    # enum. Unknown/future types fall back to `_UNSPECIFIED`.
    TYPE_ENUM = T.let({
      "IssueComment" => :TIMELINE_ITEM_TYPE_ISSUE_COMMENT,
      "IssueEvent" => :TIMELINE_ITEM_TYPE_ISSUE_EVENT,
      "PullRequestReview" => :TIMELINE_ITEM_TYPE_PULL_REQUEST_REVIEW,
      "PullRequestCommit" => :TIMELINE_ITEM_TYPE_PULL_REQUEST_COMMIT,
      "CrossReference" => :TIMELINE_ITEM_TYPE_CROSS_REFERENCE,
      "PullRequestReviewThread" => :TIMELINE_ITEM_TYPE_PULL_REQUEST_REVIEW_THREAD,
      "PullRequestRevisionMarker" => :TIMELINE_ITEM_TYPE_PULL_REQUEST_REVISION_MARKER,
      "IssueEdit" => :TIMELINE_ITEM_TYPE_ISSUE_EDIT,
    }.freeze, T::Hash[String, Symbol])

    sig { params(items: T::Array[Event]).returns(Proto::TimelineResponse) }
    def self.call(items)
      new.call(items)
    end

    sig { params(items: T::Array[Event]).returns(Proto::TimelineResponse) }
    def call(items)
      Proto::TimelineResponse.new(items: items.map { |item| build_item(item) })
    end

    private

    sig { params(item: Event).returns(Github::PullRequests::V1::TimelineItem) }
    def build_item(item)
      Proto::TimelineItem.new(
        id: item.id,
        type: TYPE_ENUM.fetch(item.type, :TIMELINE_ITEM_TYPE_UNSPECIFIED),
        timestamp: GitHub::Protobuf::Wrappers.str_value(item.timestamp&.iso8601),
        user: build_user(item.user),
        additional_info: build_additional_info(item.type, item.additional_info),
      )
    end

    sig { params(user: T.nilable(EventUser)).returns(T.nilable(Github::PullRequests::V1::TimelineUser)) }
    def build_user(user)
      return nil if user.nil?

      Proto::TimelineUser.new(
        id: user.id,
        display_login: user.display_login,
        avatar_url: user.avatar_url,
      )
    end

    # Selects the `AdditionalInfo` oneof arm by the item's `type`. Types without
    # metadata carry an empty hash and produce no message.
    sig do
      params(type: String, info: T::Hash[Symbol, T.untyped])
        .returns(T.nilable(Github::PullRequests::V1::AdditionalInfo))
    end
    def build_additional_info(type, info)
      return nil if info.empty?

      case type
      when "IssueComment"
        Proto::AdditionalInfo.new(issue_comment: build_issue_comment_info(info))
      when "IssueEvent"
        Proto::AdditionalInfo.new(issue_event: build_issue_event_info(info))
      when "PullRequestReview"
        Proto::AdditionalInfo.new(pull_request_review: build_pull_request_review_info(info))
      when "PullRequestCommit"
        Proto::AdditionalInfo.new(pull_request_commit: build_pull_request_commit_info(info))
      when "PullRequestRevisionMarker"
        Proto::AdditionalInfo.new(pull_request_revision_marker: build_pull_request_revision_marker_info(info))
      end
    end

    sig { params(info: T::Hash[Symbol, T.untyped]).returns(Github::PullRequests::V1::IssueCommentInfo) }
    def build_issue_comment_info(info)
      kwargs = {}
      kwargs[:comment_id] = info[:commentId] if info.key?(:commentId)
      Proto::IssueCommentInfo.new(**kwargs)
    end

    sig { params(info: T::Hash[Symbol, T.untyped]).returns(Github::PullRequests::V1::IssueEventInfo) }
    def build_issue_event_info(info)
      kwargs = {}
      kwargs[:event_type] = info[:eventType] if info.key?(:eventType)
      kwargs[:label] = build_label(info[:label]) if info.key?(:label)
      kwargs[:reviewer_login] = GitHub::Protobuf::Wrappers.str_value(info[:reviewerLogin]) if info.key?(:reviewerLogin)
      kwargs[:reviewer_team_slug] = GitHub::Protobuf::Wrappers.str_value(info[:reviewerTeamSlug]) if info.key?(:reviewerTeamSlug)
      kwargs[:assignee_login] = GitHub::Protobuf::Wrappers.str_value(info[:assigneeLogin]) if info.key?(:assigneeLogin)
      kwargs[:previous_title] = GitHub::Protobuf::Wrappers.str_value(info[:previousTitle]) if info.key?(:previousTitle)
      kwargs[:new_title] = GitHub::Protobuf::Wrappers.str_value(info[:newTitle]) if info.key?(:newTitle)
      kwargs[:before_commit_oid] = GitHub::Protobuf::Wrappers.str_value(info[:beforeCommitOid]) if info.key?(:beforeCommitOid)
      kwargs[:after_commit_oid] = GitHub::Protobuf::Wrappers.str_value(info[:afterCommitOid]) if info.key?(:afterCommitOid)
      kwargs[:ref] = GitHub::Protobuf::Wrappers.str_value(info[:ref]) if info.key?(:ref)
      kwargs[:dismissal_message] = GitHub::Protobuf::Wrappers.str_value(info[:dismissalMessage]) if info.key?(:dismissalMessage)
      kwargs[:commit_oid] = GitHub::Protobuf::Wrappers.str_value(info[:commitOid]) if info.key?(:commitOid)
      kwargs[:state_reason] = GitHub::Protobuf::Wrappers.str_value(info[:stateReason]) if info.key?(:stateReason)
      kwargs[:lock_reason] = GitHub::Protobuf::Wrappers.str_value(info[:lockReason]) if info.key?(:lockReason)
      Proto::IssueEventInfo.new(**kwargs)
    end

    sig { params(info: T::Hash[Symbol, T.untyped]).returns(Github::PullRequests::V1::PullRequestReviewInfo) }
    def build_pull_request_review_info(info)
      kwargs = {}
      kwargs[:state] = info[:state] if info.key?(:state)
      kwargs[:review_id] = info[:reviewId] if info.key?(:reviewId)
      kwargs[:comment_count] = GitHub::Protobuf::Wrappers.int32_value(info[:commentCount]) if info.key?(:commentCount)
      kwargs[:is_author] = GitHub::Protobuf::Wrappers.bool_value(info[:isAuthor]) if info.key?(:isAuthor)
      kwargs[:qualified_reviewer] = GitHub::Protobuf::Wrappers.bool_value(info[:qualifiedReviewer]) if info.key?(:qualifiedReviewer)
      kwargs[:reviewer_type] = info[:reviewerType] if info.key?(:reviewerType)
      kwargs[:dismissed_state] = GitHub::Protobuf::Wrappers.str_value(info[:dismissedState]) if info.key?(:dismissedState)
      Proto::PullRequestReviewInfo.new(**kwargs)
    end

    sig { params(info: T::Hash[Symbol, T.untyped]).returns(Github::PullRequests::V1::PullRequestCommitInfo) }
    def build_pull_request_commit_info(info)
      kwargs = {}
      kwargs[:sha] = info[:sha] if info.key?(:sha)
      kwargs[:base_sha] = GitHub::Protobuf::Wrappers.str_value(info[:baseSha]) if info.key?(:baseSha)
      kwargs[:short_message_text] = GitHub::Protobuf::Wrappers.str_value(info[:shortMessageText]) if info.key?(:shortMessageText)
      Proto::PullRequestCommitInfo.new(**kwargs)
    end

    sig do
      params(info: T::Hash[Symbol, T.untyped])
        .returns(Github::PullRequests::V1::PullRequestRevisionMarkerInfo)
    end
    def build_pull_request_revision_marker_info(info)
      kwargs = {}
      kwargs[:last_seen_commit_oid] = GitHub::Protobuf::Wrappers.str_value(info[:lastSeenCommitOid]) if info.key?(:lastSeenCommitOid)
      Proto::PullRequestRevisionMarkerInfo.new(**kwargs)
    end

    sig { params(label: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(Github::PullRequests::V1::Label)) }
    def build_label(label)
      return nil if label.nil?

      kwargs = {}
      kwargs[:name] = label[:name] if label.key?(:name)
      kwargs[:color] = label[:color] if label.key?(:color)
      Proto::Label.new(**kwargs)
    end
  end
end
