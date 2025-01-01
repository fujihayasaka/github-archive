# typed: true
# frozen_string_literal: true

class Timeline::Placeholder
  def self.async_value_for(object)
    return Promise.resolve(object) unless object.respond_to?(:async_value)
    object.async_value
  end

  # Internal: Base class for timeline placeholders
  #
  # The subclasses of this class implement concrete placeholder types like issue
  # comments or PR commits. A placeholder represents the minimal amount of information
  # necessary to be able to sort and paginate the timeline and subsequentally load the
  # placeholder's value.
  class Base
    include GitHub::Relay::GlobalIdentification

    def platform_type_name
      type_name
    end

    # Plain text ID, e.g. `"<database_id>"` (for an ActiveRecord object)
    # or `"<pull_request_id>:<commit_oid>"` for a PR commit. It is the value that `#id` does
    # return on objects of these types.
    #
    # Note: This is not the return value of #global_relay_id (which returns the encoded
    # global ID).
    attr_reader :id

    # Array of DateTimes used for sorting the timeline placeholders
    attr_reader :sort_datetimes

    def initialize(id:, sort_datetimes:)
      @id = id
      @sort_datetimes = sort_datetimes
    end

    def ==(other)
      super || (
        other.instance_of?(self.class) &&
        !id.nil? &&
        id == other.id &&
        sort_datetimes == other.sort_datetimes
      )
    end

    # Public: Provides a promise resolving the value of the placeholder
    #
    # Returns a Promise
    def async_value
      return @async_value if defined?(@async_value)

      @async_value = Platform::Schema.get_type(type_name).load_from_global_id(id)
    end

    # Public: The sort key used for sorting. Includes `#sort_datetimes`, the
    # sort priority and finally the ID. The latter two are tie-breakers for when
    # the timestamps are the same.
    #
    # This way we ensure stable sorting of the timeline elements.
    #
    # Returns Array of 1) Array of Datetimes, 2) priority number, 3) identifier
    def sort_key
      return @sort_key if defined?(@sort_key)

      @sort_key = [
        sort_datetimes,
        sort_priority,
        id,
      ]
    end

    # Public: The cursor key used for generating cursors.
    #
    # TODO: Once `sort_datetimes` becomes a single timestamp, `sort_key` can become an
    # alias of `cursor_key`.
    #
    # Returns Array of 1) datetime as Integer, 2) priority number, 3) identifier
    def cursor_key
      return @cursor_key if defined?(@cursor_key)

      @cursor_key = [
        (sort_datetimes.first.to_f * 1000).to_i, # include microseconds in timestamp value
        sort_priority,
        id.to_s,
      ]
    end

    # Public: Timestamp used for filtering by creation DateTime
    #
    # Returns DateTime
    def filter_datetime
      sort_datetimes.first
    end

    private

    def type_name
      raise NotImplementedError, "needs to be implemented by subclass"
    end

    def sort_priority
      raise NotImplementedError, "needs to be implemented by subclass"
    end
  end

  # Public: Timeline placeholder for `IssueComment`s
  class IssueComment < Base
    private

    def type_name
      "IssueComment"
    end

    def sort_priority
      0
    end
  end

  # Public: Timeline placeholder for `IssueEvent`s
  class IssueEvent < Base
    attr_reader :event_name, :commit_oid

    def initialize(event_name:, commit_oid: nil, **attributes)
      super(**T.unsafe(attributes))
      @event_name = event_name
      @commit_oid = commit_oid
    end

    def ==(other)
      super && event_name == other.event_name && commit_oid == other.commit_oid
    end

    def sort_priority
      1
    end

    def type_name
      ::IssueEvent.column_to_platform_type_name(event_name)
    end
  end

  # Public: Timeline placeholder for `CrossReference`s
  class CrossReference < Base
    def sort_priority
      2
    end

    def type_name
      "CrossReferencedEvent"
    end
  end

  # Public: Timeline placeholder for `PullRequestReviewThread`s
  class PullRequestReviewThread < Base
    attr_accessor :database_id

    def sort_priority
      3
    end

    def type_name
      "PullRequestReviewThread"
    end
  end

  # Public: Timeline placeholder for `PullRequestCommitCommentThread`s
  class PullRequestCommitCommentThread < Base
    attr_accessor :commit_oid

    def sort_priority
      4
    end

    def type_name
      "PullRequestCommitCommentThread"
    end
  end

  # Public: Timeline placeholder for `PullRequestReview`s
  class PullRequestReview < Base
    attr_reader :filter_datetime

    def initialize(filter_datetime:, **attributes)
      super(**T.unsafe(attributes))
      @filter_datetime = filter_datetime
    end

    private

    def sort_priority
      5
    end

    def type_name
      "PullRequestReview"
    end
  end

  class MemexProjectEvent < Base
    attr_reader :id, :issue_id, :memex_id, :actor_id, :created_at

    def initialize(id:, issue_id:, sort_datetimes:, memex_id:, was_automated:, actor_id:, created_at:)
      super(id: id, sort_datetimes: sort_datetimes)

      @id = id
      @issue_id = issue_id
      @sort_datetimes = sort_datetimes
      @memex_id = memex_id
      @was_automated = was_automated
      @actor_id = actor_id
      @created_at = created_at
    end

    def global_id
      "#{issue_id}:#{id}"
    end

    # This placeholder isn't backed by an Active Record model. Just return itself since it got everything we need.
    def async_value
      Promise.resolve(self)
    end

    def async_actor
      Platform::Loaders::ActiveRecord.load(::User, actor_id)
    end

    def automated?
      @was_automated
    end

    def sort_priority
      5
    end

    def async_memex_project
      Platform::Loaders::ActiveRecord.load(MemexProject, memex_id)
    end

    def async_issue
      Platform::Loaders::ActiveRecord.load(::Issue, issue_id)
    end

    def async_performed_via_integration
      Promise.resolve(nil)
    end
  end

  class AddedToMemexProject < MemexProjectEvent
    def platform_type_name
      "AddedToProjectV2Event"
    end
  end

  class RemovedFromMemexProject < MemexProjectEvent
    def platform_type_name
      "RemovedFromProjectV2Event"
    end
  end

  class ProjectItemStatusChanged < MemexProjectEvent
    attr_reader :status, :previous_status
    def initialize(id:, issue_id:, sort_datetimes:, memex_id:, was_automated:, actor_id:, created_at:, status:, previous_status:)
      super(
        id: id,
        issue_id: issue_id,
        sort_datetimes: sort_datetimes,
        memex_id: memex_id,
        was_automated: was_automated,
        actor_id: actor_id,
        created_at: created_at
      )
      @status = status
      @previous_status = previous_status
    end

    def platform_type_name
      "ProjectV2ItemStatusChangedEvent"
    end
  end

  class ConvertedFromDraft < MemexProjectEvent
    def platform_type_name
      "ConvertedFromDraftEvent"
    end
  end

  # Public: Timeline placeholder for `PullRequestRevisionMarker`s
  class PullRequestRevisionMarker < Base
    attr_reader :last_seen_commit_oid
    attr_writer :sort_datetimes
    attr_accessor :pull_request

    def initialize(last_seen_commit_oid:)
      @last_seen_commit_oid = last_seen_commit_oid
    end

    def ==(other)
      self.equal?(other) || (other.instance_of?(self.class) && last_seen_commit_oid == other.last_seen_commit_oid && sort_datetimes == other.sort_datetimes)
    end

    def sort_priority
      6
    end

    def async_value
      return @async_value if defined?(@async_value)

      value = ::PullRequestRevisionMarker.new(
        pull_request,
        last_seen_commit_oid,
        sort_datetimes.first,
      )
      @async_value = Promise.resolve(value)
    end

    def type_name
      "PullRequestRevisionMarker"
    end
  end

  # Public: Timeline placeholder for `PullRequestCommit`s
  class PullRequestCommit < Base
    attr_reader :oid, :author_email, :pull_request

    def initialize(oid:, author_email:, pull_request:, **attributes)
      super(**T.unsafe(attributes))
      @oid = oid
      @author_email = author_email
      @pull_request = pull_request
    end

    def ==(other)
      super && oid == other.oid && author_email == other.author_email
    end

    def sort_priority
      7
    end

    def type_name
      "PullRequestCommit"
    end

    def async_author
      return @async_author if defined?(@async_author)
      @async_author = Platform::Loaders::UserByEmail.load(author_email)
    end

    # Public: The sort key used for sorting. Includes `#sort_datetimes`, the
    # sort priority and either the ID or, if using the ordering from rev-list,
    # an empty string. The latter two are tie-breakers for when the timestamps
    # are the same. When using rev-list ordering, the tie-breaker is the prior
    # positions of the elements in the list, hence using constants for those
    # values.
    #
    # This way we ensure stable sorting of the timeline elements.
    #
    # Returns Array of 1) Array of Datetimes, 2) priority number, 3) String
    def sort_key
      return @sort_key if defined?(@sort_key)

      @sort_key = [
        sort_datetimes,
        sort_priority,
        "",
      ]
    end
  end
end
