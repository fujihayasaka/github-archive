# typed: true
# frozen_string_literal: true

class IssueEvent::Loader
  include GitHub::UTF8
  include ::GitHub::Memoizer
  include Scientist

  DEPLOYMENT_EVENTS = %w(deployed deployment_environment_changed).freeze
  ATTRIBUTES_FOR_FILTERING = %w(referencing_issue_id commit_id).freeze
  ATTRIBUTES_FOR_DETAILS = %w(label_id label_name subject_id subject_type deployment_id).freeze
  BATCH_LIMIT = 1_000
  LOAD_FIRST_BUFFER = 10

  def initialize(viewer, base_scope:, selected_attributes:, visible_events_only: false, exclude_event_types: [], requested_events: [])
    @viewer = viewer
    @base_scope = base_scope
    @selected_attributes = selected_attributes
    @visible_events_only = visible_events_only
    @exclude_event_types = exclude_event_types
    @requested_events = requested_events.empty? ? IssueEvent::VALID_EVENTS : requested_events

    @issue_events = []
  end

  def load_first(first)
    limit = first + LOAD_FIRST_BUFFER
    ids = load_events_with_limit limit

    load_all_events_from_ids(ids)

    if @issue_events.empty?
      GitHub.dogstats.increment("issue_event.loader.load_first", tags: ["result:empty"])
      return @issue_events
    end

    has_more_events = @issue_events.length == limit

    load_associated_events_data
    filter_events

    if @issue_events.length < first && has_more_events
      GitHub.dogstats.increment("issue_event.loader.load_first", tags: ["result:fallback"])
      @issue_events = []
      return load
    end

    GitHub.dogstats.increment("issue_event.loader.load_first", tags: ["result:success"])
    map_results @issue_events
  end

  def load
    GitHub.dogstats.increment("issue_event.loader.load")

    load_all_events
    return @issue_events if @issue_events.empty?

    load_associated_events_data
    filter_events

    map_results @issue_events
  end

  private

  attr_reader :issues_by_id,
    :pull_requests_id,
    :repositories_by_id,
    :deployments_by_id

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def load_all_events_unbatched
    sql_query = @base_scope.
      where(event: events).
      select(escaped_selected_attributes).
      joins("LEFT JOIN `issue_event_details` ON `issue_event_details`.`issue_event_id` = `issue_events`.`id`").
      limit_execution_time(limit_ms: 500).
      to_sql
    @issue_events = IssueEvent.connection.select_all(sql_query).to_a
  end

  sig { params(ids: T::Array[Integer]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def load_all_events_from_ids(ids)
    results = []
    base_scope = @base_scope.
      select(escaped_selected_attributes).
      joins("LEFT JOIN `issue_event_details` ON `issue_event_details`.`issue_event_id` = `issue_events`.`id`")

    ids.each_slice(BATCH_LIMIT).map do |id_batch|
      IssueEvent.connection.select_all(base_scope.where(id: id_batch).to_sql, async: true)
    end.each do |id_batch_promise|
      results.concat(id_batch_promise.result.to_a)
    end
    @issue_events = results
  end

  sig { returns(T::Array[Integer]) }
  def load_all_events_ids
    @base_scope.where(event: events).ids
  end

  sig { returns(T::Array[[Integer, String]]) }
  def load_all_events_ids_and_sort_field
    @base_scope.where(event: events).pluck(:id, :created_at)
  end

  sig { params(limit: Integer).returns(T::Array[Integer]) }
  def load_events_with_limit(limit)
    events = load_all_events_ids_and_sort_field
    events.sort_by { |event| event[1] }.first(limit).map { |event| event[0] }
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def load_all_events
    begin
      load_all_events_unbatched
    rescue ActiveRecord::StatementTimeout
      GitHub.dogstats.increment("issue_event.loader.batched_timeout")
      ids = load_all_events_ids
      load_all_events_from_ids(ids)
    end
  end

  sig { returns(T::Array[String]) }
  memoize def events
    @visible_events_only ? @requested_events - IssueEvent::INVISIBLE_EVENTS : @requested_events
  end

  def escaped_selected_attributes
    @escaped_selected_attributes ||= @selected_attributes +
      %w[event raw_data] +
      ATTRIBUTES_FOR_FILTERING.map do |attribute|
        "`issue_events`.`#{attribute}`"
      end +
      ATTRIBUTES_FOR_DETAILS.map do |attribute|
        "`issue_event_details`.`#{attribute}`"
      end
  end

  def load_issues
    return @issues_by_id if @issues_by_id

    issue_ids = (
      events_by_types(IssueEvent::PULL_REQUEST_EVENTS + IssueEvent::FORCE_PUSH_EVENTS).
          map { |event| event["issue_id"] }.compact.uniq +
      subject_issue_ids
    ).uniq

    @issues_by_id = Issue.
      where(id: issue_ids).
      select(:id, :pull_request_id, :repository_id, :user_hidden, :user_id).
      index_by(&:id)
  end

  def events_by_types(types)
    return @events_by_types[types] if defined?(@events_by_types)

    @events_by_types = Hash.new do |hash, types|
      hash[types] = @issue_events.select { |event| types.include?(event["event"]) }
    end

    @events_by_types[types]
  end

  def subject_issue_ids
    return @subject_issue_ids if @subject_issue_ids

    @subject_issue_ids = events_by_types(IssueEvent::CROSS_ISSUE_SUBJECT_EVENTS).
      map do |event|
        event["subject_id"] if event["subject_type"] == "Issue"
      end.compact.uniq
  end

  def load_associated_events_data
    load_issues
    load_pull_requests
    load_repositories
    load_deployments
  end

  def filter_events
    filter_label_events!
    filter_pull_request_events!
    filter_referenced_events!
    filter_deployed_events!
    filter_cross_issue_subject_events!
    filter_force_push_events!
  end

  def load_pull_requests
    return @pull_requests_by_id if @pull_requests_by_id

    pull_request_events = events_by_types(IssueEvent::PULL_REQUEST_EVENTS +
      IssueEvent::FORCE_PUSH_EVENTS)

    pull_request_ids = pull_request_events.
      map { |event| @issues_by_id[event["issue_id"]]&.pull_request_id }.
      compact.uniq

    @pull_requests_by_id = PullRequest.where(id: pull_request_ids).index_by(&:id)
  end

  def load_repositories
    return @repositories_by_id if @repositories_by_id

    repo_ids = (
      subject_issue_repository_ids +
      commit_repository_ids
    ).uniq

    @repositories_by_id = Repository.
      where(id: repo_ids).
      index_by(&:id)
  end

  def subject_issue_repository_ids
    subject_issue_ids.map do |id|
      issues_by_id[id]&.repository_id
    end.uniq.compact
  end

  def subject_issues_by_id
    subject_issue_ids.map do |id|
      issues_by_id[id]
    end
  end

  def load_deployments
    return @deployments_by_id if @deployments_by_id

    deployment_ids = @issue_events.map do |event|
      event["deployment_id"] if DEPLOYMENT_EVENTS.include?(event["event"])
    end.compact.uniq

    @deployments_by_id = Deployment.
      where(id: deployment_ids).
      select(:id).
      index_by(&:id)
  end

  def commit_repository_ids
    events_by_types(IssueEvent::FORCE_PUSH_EVENTS + ["referenced"]).
      map { |event| event["commit_repository_id"] }.compact.uniq
  end

  def filter_events!(events)
    return unless (events = events & @requested_events).any?

    @issue_events = @issue_events.select do |event|
      next true unless events.include?(event["event"])
      yield(event)
    end
  end

  def filter_label_events!
    filter_events!(IssueEvent::LABEL_EVENTS) do |event|
      if event["label_id"] || event["label_name"]
        true
      else
        GitHub.dogstats.increment("issue_event.invalid_label_event")
        false
      end
    end
  end

  def filter_pull_request_events!
    filter_events!(IssueEvent::PULL_REQUEST_EVENTS) do |event|
      associated_with_pull_request?(event)
    end
  end

  def associated_with_pull_request?(event)
    return false unless event["issue_id"]
    issue = issues_by_id[event["issue_id"]]
    return false unless issue&.pull_request_id
    @pull_requests_by_id[issue.pull_request_id] != nil
  end

  def filter_referenced_events!
    filter_events!(["referenced"]) do |event|
      event["referencing_issue_id"].nil? &&
      event["commit_id"] != nil &&
      !spammy_commit_repository?(event)
    end
  end

  def spammy_commit_repository?(event)
    commit_repository_id = event["commit_repository_id"]
    return false unless GitHub.spamminess_check_enabled?
    return false if commit_repository_id.nil?
    return false if @viewer&.site_admin?
    return false unless repositories_by_id.keys.include?(commit_repository_id)

    commit_repository = repositories_by_id[commit_repository_id]

    return false unless commit_repository

    if @viewer
      commit_repository.user_hidden != 0 &&
        commit_repository.owner_id != @viewer.id
    else
      commit_repository.user_hidden != 0
    end
  end

  def filter_deployed_events!
    filter_events!(DEPLOYMENT_EVENTS) do |event|
      deployments_by_id[event["deployment_id"]]
    end
  end

  def filter_cross_issue_subject_events!
    filter_events!(IssueEvent::CROSS_ISSUE_SUBJECT_EVENTS) do |event|
      next false unless subject_issue = issues_by_id[event["subject_id"]]
      next false unless repositories_by_id[subject_issue.repository_id]

      event["referencing_issue_id"].nil? &&
      event["subject_id"] != nil &&
      !spammy_subject?(event) &&
      !spammy_subject_repository?(event)
    end
  end

  def spammy_subject?(event)
    return false unless GitHub.spamminess_check_enabled?
    return false if @viewer&.site_admin?

    subject_issue = issues_by_id[event["subject_id"]]

    return false unless subject_issue

    if @viewer
      subject_issue.user_hidden != 0 &&
        subject_issue.user_id != @viewer.id
    else
      subject_issue.user_hidden != 0
    end
  end

  def spammy_subject_repository?(event)
    return false unless GitHub.spamminess_check_enabled?
    return false if @viewer&.site_admin?

    subject_issue = issues_by_id[event["subject_id"]]

    return false unless subject_issue

    subject_issue_repository = repositories_by_id[subject_issue.repository_id]

    return false unless subject_issue_repository

    if @viewer
      subject_issue_repository.user_hidden != 0 &&
        subject_issue_repository.owner_id != @viewer.id
    else
      subject_issue_repository.user_hidden != 0
    end
  end

  def filter_force_push_events!
    filter_events!(IssueEvent::FORCE_PUSH_EVENTS) do |event|
      commit_repository = repositories_by_id[event["commit_repository_id"]]
      associated_with_pull_request?(event) && commit_repository != nil
    end
  end

  def map_results(events)
    events.map do |event|
      @selected_attributes.map do |attribute|
        [attribute, event[attribute.to_s]]
      end.to_h
    end
  end
end
