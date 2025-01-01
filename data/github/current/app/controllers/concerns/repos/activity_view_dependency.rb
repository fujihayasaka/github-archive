# typed: true
# frozen_string_literal: true

module Repos::ActivityViewDependency
  extend T::Helpers

  include ApplicationHelper
  include TextHelper
  include CurrentRepositoryInteractionsHelper
  include BranchesHelper
  include Repositories::Domain::Provider

  abstract!

  sig { abstract.returns(T.nilable(ActionDispatch::Request)) }
  def request; end

  # Prior to this date, we did not reliably write Pushes to the database.
  # We will limit the visibility of pushes in the Activity View to this date and later.
  RELIABLE_PUSH_DATA_TIME = T.let(Time.new(2023, 3, 7).freeze, Time)

  # Avoid overriding const values from API by adding WEB_UI suffix
  # When changing server-side constant here, make sure to update client-side code as well
  DEFAULT_PER_PAGE_WEB_UI = 30
  MAX_PER_PAGE_WEB_UI = 100

  ACTIVITY_TYPES = %w[all push force_push branch_creation branch_deletion pr_merge direct_push merge_queue_merge].freeze
  TIME_PERIODS = %w[all day week month quarter year].freeze
  SORT_OPTIONS = %w[ASC DESC].freeze

  # Inherits from ApplicationController
  def current_repository
    super
  end

  def current_user
    super
  end

  def params
    super
  end

  def create_branch_path(owner, repo, name:, branch:, show_recreate_flash:)
    super
  end

  # Inherited from ApplicationController::AuthenticityTokenDependency in ApplicationController
  def csrf_tokens
    super
  end

  def commit_sha
    super
  end

  # Inherited from ApplicationController::FeatureFlagsDependency in ApplicationController
  def client_feature_flags
    super
  end

  # Fetches the last commit for every push in a list.
  def fetch_last_commits(pushes)
    current_repository.read_objects(
      pushes
      .map(&:after), :commit, true, feature_flag: :activity_view_dependency_read_objects_spokes_api)
      .map { |commit| Commit.new(current_repository, commit) }.map { |commit| [commit.oid, commit] }.to_h
  end

  # Current ref/branch name from the query params.
  def current_ref
    # If no ref parameter is present, we default to showing pushes for all branches
    return nil unless valid_ref_param

    if tree_name.present? && !tree_name.starts_with?("refs/")
      @current_ref = "refs/heads/#{tree_name}"
    else
      @current_ref = tree_name
    end
  end

  def tree_name
    @tree_name ||= (params[:ref] if valid_ref_param) || current_repository.default_branch
  end

  # Returns true if the ref param exists and is valid, or false if it is invalid or doesn't exist.
  def valid_ref_param
    return true if params[:ref].present? && params[:ref].is_a?(String)
    false
  end

  # Converts activerecord Pusher to json format.
  def to_json_pusher(pusher)
    return nil if pusher.nil?

    {
      login: pusher.display_login,
      name: pusher.profile_name,
      path: path_for(pusher),
      primary_avatar_url: pusher.primary_avatar_url(80)
    }
  end

  # Converts activerecord Push to json format.
  def to_json_push(push, last_commit: nil, restore_oid: nil)

    json_push = {
      before: push.created? ? nil : push.before,
      after: push.deleted? ? nil : push.after,
      ref: push.ref,
      pushed_at: push.pushed_at,
      push_type: push.push_type,
      commits_count: (push.created? || push.deleted? || push.force_push_push_type?) ? 0 : push.rev_list.count, # Avoid calls for created/deleted/force_push_push_type here. We handle such cases separetely below.
      pusher: to_json_pusher(push.pusher)
    }

    if push.force_push_push_type? && current_user&.feature_enabled?(:pushes_forced_ahead_behind)
      ahead_behind_hash = current_repository.rpc.ahead_behind(push.before, [push.after])
      json_push[:ahead_behind] = ahead_behind_hash[push.after]
    end

    if last_commit.present?
      json_push[:commit] = to_json_commit(last_commit)
    end

    if restore_oid.present?
      restore_url = create_branch_path(current_repository.owner, current_repository, name: push.ref, branch: restore_oid, show_recreate_flash: true)
      T.unsafe(self).add_csrf_token(restore_url, :post)
      json_push[:restore_url] = restore_url
    end

    json_push
  end

  # Convert GitRPC Commit to json format.
  def to_json_commit(commit)
    {
      message: commit.message,
      short_message_html_link: (commit_message_markdown(commit.short_message_html) unless commit.short_message_html.blank?),
    }
  end

  # For branch deletions, check which refs do not currently exist and fetch the before sha for the last push in those refs.
  def fetch_restore_oids(pushes)
    deleted_refs = pushes.select(&:deleted?).map(&:ref).uniq
    refs_to_restore = deleted_refs.map { |ref| current_repository.heads.exist?(ref) ? nil : ref }.compact

    restore_oids = {}
    latest_pushes = T.let(nil, T.nilable(GH::Domain::CursorCollection[Repositories::Push]))

    until refs_to_restore.empty? || latest_pushes.present? && !latest_pushes.has_next_page?
      latest_pushes = repositories_domain.pushes.by_after_and_refs(
        repository_id: current_repository.id,
        after: GitHub::NULL_OID,
        refs: refs_to_restore,
        pagination: GH::Pagination::Cursor.new(after: latest_pushes&.end_cursor)
      )

      latest_pushes.to_a.group_by(&:ref).map do |ref, pushes|
        restore_oids[ref] = pushes.last&.before
        refs_to_restore.delete(ref)
      end
    end

    restore_oids
  end

  sig { params(time_period: T.nilable(String), pushed_after: T.nilable(Time)).returns(T.nilable(Time)) }
  def convert_time_period_to_time(time_period, pushed_after)
    time = nil

    case time_period
    when "day"
      time = 1.day.ago
    when "week"
      time = 1.week.ago
    when "month"
      time = 1.month.ago
    when "quarter"
      time = 3.months.ago
    when "year"
      time = 1.year.ago
    end

    # Use the most recent date between the converted time_period query param and the pushed_after override param
    time = [time, pushed_after].compact.max if time.present? || pushed_after.present?

    time
  end

  def parse_params
    # ensure per_page is valid for WEB_UI
    # API always override this value by providing `per_page` kwarg explicitly on top of parse_params
    # See app/api/repository_activities.rb
    per_page = begin
      Integer(params[:per_page])
    rescue TypeError, ArgumentError
      DEFAULT_PER_PAGE_WEB_UI
    end
    per_page = DEFAULT_PER_PAGE_WEB_UI if per_page <= 0
    per_page = MAX_PER_PAGE_WEB_UI if per_page > MAX_PER_PAGE_WEB_UI

    # ensure activity_type is valid
    activity_type = ACTIVITY_TYPES.include?(params[:activity_type]) ? params[:activity_type] : "all"

    # ensure actor is valid if it exists
    actor_filter_present = params[:actor].present?
    actor = User.find_by_login(params[:actor]) if params[:actor].present?

    # ensure time period is valid
    time_period = TIME_PERIODS.include?(params[:time_period]) ? params[:time_period] : "all"

    # ensure sort is valid
    sort_param = (params[:sort] || params[:direction]).to_s.upcase
    sort = SORT_OPTIONS.include?(sort_param) ? sort_param : "DESC"

    before = params[:before]
    after = params[:after]

    { activity_type:, actor:, actor_filter_present:, time_period:, sort:, before:, after:, per_page: }
  end

  def index_payload(pushed_after: nil)
    parsed_params = parse_params
    parsed_params[:pushed_after] = pushed_after

    pushes_collection = fetch_pushes_from_domain(
      repository_id: current_repository.id,
      ref: current_ref,
      per_page: parsed_params[:per_page],
      sort: parsed_params[:sort],
      activity_type: parsed_params[:activity_type],
      actor: parsed_params[:actor],
      actor_filter_present: parsed_params[:actor_filter_present],
      time_period: parsed_params[:time_period],
      pushed_after: parsed_params[:pushed_after],
      before: parsed_params[:before],
      after: parsed_params[:after]
    )

    # Fetch the last commit for each push, to display in the push description
    last_commits = fetch_last_commits(pushes_collection)

    # Fetch the last oid for deleted refs to optionally restore to
    restore_oids = current_user_can_push? ? fetch_restore_oids(pushes_collection) : {}

    {
      feedback_url: current_user&.employee? ? "https://github.com/github/repos/discussions/2560" : "https://github.com/orgs/community/discussions/53140",
      repo: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: current_user_can_push?
      ),
      ref_info: {
        name: current_ref.present? ? tree_name : "",
        list_cache_key: ref_list_cache_key,
        current_oid: current_ref.present? ? commit_sha : ""
      },
      activity_list: {
        items: pushes_collection.map { |push| to_json_push(push, last_commit: last_commits[push.after], restore_oid: push.deleted? && !push.ref_is_tag? ? restore_oids[push.ref] : nil) },
        has_next_page: pushes_collection.has_next_page?,
        has_previous_page: pushes_collection.has_previous_page?,
        activity_type: parsed_params[:activity_type],
        actor: to_json_pusher(parsed_params[:actor]),
        time_period: parsed_params[:time_period],
        sort: parsed_params[:sort],
        per_page: parsed_params[:per_page],
        start_cursor: pushes_collection.start_cursor,
        end_cursor: pushes_collection.end_cursor
      }
    }
  end

  sig do params(
    repository_id: Integer,
    ref: T.nilable(String),
    per_page: T.nilable(Integer),
    sort: T.nilable(String),
    activity_type: T.nilable(String),
    actor: T.nilable(User),
    actor_filter_present: T.nilable(T::Boolean),
    time_period: T.nilable(String),
    pushed_after: T.nilable(Time),
    first: T.nilable(Integer),
    last: T.nilable(Integer),
    before: T.nilable(String),
    after: T.nilable(String)
  ).returns(GH::Domain::CursorCollection[Repositories::Push])
  end
  def fetch_pushes_from_domain(repository_id:, ref:, per_page: DEFAULT_PER_PAGE_WEB_UI, sort: "DESC", activity_type: "all", actor: nil, actor_filter_present: nil, time_period: "year", pushed_after: nil, first: nil, last: nil, before: nil, after: nil)
    before = valid_cursor_or_nil(before)
    after = valid_cursor_or_nil(after)

    if first.nil? && last.nil?
      # If no first/last params are present, we just want the page of results closest to the cursor.
      # i.e. the "last" results if we're paginating backwards, and the "first" results if we're paginating forwards.
      first, last = before.present? ? [nil, per_page] : [per_page, nil]
    end

    pagination = GH::Pagination::Cursor.new(after: after, before: before, first:, last:)

    if actor_filter_present && actor.nil?
      return GH::Domain::CursorCollection.new(members: [], has_previous_page: false, has_next_page: false, lazy_total_entries: nil, lazy_cursor: nil)
    end

    repositories_domain.pushes.by_activity_filters(
      repository_id:,
      pagination:,
      sort: GH::Pagination::Sort::Direction.from_string(sort),
      ref:,
      activity_type:,
      pusher_id: actor&.id,
      pushed_after: convert_time_period_to_time(time_period, pushed_after)
    )
  end

  def valid_cursor_or_nil(cursor)
    cursor.present? && Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(cursor) ? cursor : nil
  rescue Platform::Errors::Cursor
    nil
  end
end
