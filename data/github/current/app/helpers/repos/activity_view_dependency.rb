# typed: true
# frozen_string_literal: true

module Repos::ActivityViewDependency
  extend T::Sig
  extend T::Helpers

  include ApplicationHelper
  include TextHelper
  include ReactHelper
  include CurrentRepositoryInteractionsHelper
  include BranchesHelper

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

  def commit_sha
    super
  end

  # Fetches pushes from the database.
  #
  # @param per_page Integer – Number of pushes to fetch to show on a single page.
  # @param sort String – The direction to sort the pushes by.
  # @param activity_type String – The activity type to filter by. For example "force_push", to see all force pushes to the repository.
  # @param actor User – Filter by the actor who performed the activity.
  # @param actor_filter_present Boolean – Whether the actor filter was provided by the customer or not.
  # @param time_period String – The time period to filter by. For example, `day` will filter for activity that occurred in the past 24 hours, and `week` will filter for activity that occurred in the past 7 days (168 hours).
  # @param pushed_after DateTime – Using this param we limit the visibility of pushes in the Activity View to RELIABLE_PUSH_DATA_TIME and later. Should be always passed for customer facing code. Only for Stafftools we can show all the data.
  # @param first Integer – Similar to per_page, but also sets the pagination direction from the begining of the collection. Used in v2 pagination/cursor logic.
  # @param last Integer – Similar to per_page, but also sets the pagination direction from the end of the collection. Used in v2 pagination/cursor logic.
  # @param before String – Find pushes before the given cursor.
  # @param after String – Find pushes after the given cursor.
  def fetch_pushes(per_page: DEFAULT_PER_PAGE_WEB_UI, sort: "DESC", activity_type: "all", actor: nil, actor_filter_present: nil, time_period: "year", pushed_after: nil, first: nil, last: nil, before: nil, after: nil)
    base_sql = current_repository
      .pushes
      .preload(:pusher)
      .limit(per_page + 1) # fetch one additional push to see if there is another page of pushes
      .order(pushed_at: sort, id: sort)

    # If first/last args are present that means we're using v2 pagination/cursor.
    # For now we only use it in GraphQL, but we're aiming to try it in the UI/REST as well.
    forward_pagination = first.present?
    backward_pagination = last.present?

    base_sql = base_sql.reverse_order if backward_pagination

    base_sql = base_sql.where(ref: current_ref) if current_ref.present?

    case activity_type
    when "push"
      base_sql = base_sql.push_push_type
    when "force_push"
      base_sql = base_sql.force_push_push_type
    when "branch_creation"
      base_sql = base_sql.branch_creation_push_type
    when "branch_deletion"
      base_sql = base_sql.branch_deletion_push_type
    when "pr_merge"
      base_sql = base_sql.pr_merge_push_type
    when "direct_push"
      base_sql = base_sql.direct_push
    when "merge_queue_merge"
      base_sql = base_sql.merge_queue_merge_push_type
    end

    pushed_at = convert_time_period_to_time(time_period, pushed_after)
    if pushed_at.present?
      base_sql = base_sql.where(pushed_at: pushed_at..)
    end

    if actor_filter_present
      base_sql = if actor.present?
        base_sql.where(pusher_id: actor.id)
      else
        base_sql.none
      end
    end

    # If the incoming request is for a new page of pushes, there will be a cursor present
    # Check to make sure we decode a valid cursor before attempting to load another page
    #
    # page is the current page number that the request is coming from, not the new page number being requested
    #
    # cursor_id is the id of the first push on the first page of pushes when the user loaded the activity view.
    # We need this starting id when sorting pushes in most recent first order (DESC) to ensure that
    # new push records, which would appear at the front of the list, will not cause pushes to shift between pages.
    # We don't need to do this when sorting in ascending order (ASC) because new pushes will appear at the end of the list.
    if before.present? || after.present?
      decoded_cursor_version, cursor_id, page, cursor_timestamp = decode_cursor(before || after)

      if decoded_cursor_version == "v1" && cursor_id.present? && page.present?
        if after
          page += 1
        elsif before && page > 0
          page -= 1
        end
        has_previous_page = page > 0
        # If we are sorted in descending push order, ensure new push records do not appear at the front of the list
        base_sql = base_sql.where(id: ..cursor_id) if sort == "DESC"
        # We will offset by the page size * page number to load the next or previous page
        base_sql = base_sql.offset(per_page * page)
      elsif decoded_cursor_version == "v2" && cursor_id.present?
        # TODO: Reuse Relation::Condition from Platform::ConnectionWrappers for building the queries below when it will be possible.
        if after
          if sort == "ASC"
            # Reverse pagination check looks for items on the other side of the cursor.
            has_previous_page = base_sql.dup.where("pushed_at < :cursor_timestamp OR (pushed_at = :cursor_timestamp AND id <= :cursor_id)", { cursor_id:, cursor_timestamp: }).limit(1).any? if forward_pagination
            base_sql = base_sql.where("pushed_at > :cursor_timestamp OR (pushed_at = :cursor_timestamp AND id > :cursor_id)", { cursor_id:, cursor_timestamp: })
          elsif sort == "DESC"
            # Reverse pagination check looks for items on the other side of the cursor.
            has_previous_page = base_sql.dup.where("pushed_at > :cursor_timestamp OR (pushed_at = :cursor_timestamp AND id >= :cursor_id)", { cursor_id:, cursor_timestamp: }).limit(1).any? if forward_pagination
            base_sql = base_sql.where("pushed_at < :cursor_timestamp OR (pushed_at = :cursor_timestamp AND id < :cursor_id)", { cursor_id:, cursor_timestamp: })
          end
        elsif before
          if sort == "ASC"
            # Reverse pagination check looks for items on the other side of the cursor.
            has_next_page = base_sql.dup.where("pushed_at > :cursor_timestamp OR (pushed_at = :cursor_timestamp AND id >= :cursor_id)", { cursor_id:, cursor_timestamp: }).limit(1).any? if backward_pagination
            base_sql = base_sql.where("pushed_at < :cursor_timestamp OR (pushed_at = :cursor_timestamp AND id < :cursor_id)", { cursor_id:, cursor_timestamp: })
          elsif sort == "DESC"
            # Reverse pagination check looks for items on the other side of the cursor.
            has_next_page = base_sql.dup.where("pushed_at < :cursor_timestamp OR (pushed_at = :cursor_timestamp AND id <= :cursor_id)", { cursor_id:, cursor_timestamp: }).limit(1).any? if backward_pagination
            base_sql = base_sql.where("pushed_at > :cursor_timestamp OR (pushed_at = :cursor_timestamp AND id > :cursor_id)", { cursor_id:, cursor_timestamp: })
          end
        end
      end
    end

    # When there are no selected filters other than time filter or no filters at all,
    # and no pagination or only OFFSET pagination without v2 cursor,
    # basically when we don't emit a `WHERE` clause on any column other than `pushed_at`,
    # we should hit `repository_id_and_pushed_at_index` index.
    # However, MySQL occasionally chooses a different index and the query becomes slow.
    # So, in such cases we want to use an index hint.
    should_hit_repository_id_and_pushed_at_index = !current_ref.present? && # no branch filter
      activity_type == "all" && # no activity type filter
      !actor_filter_present && # no actor filter
      (!decoded_cursor_version || decoded_cursor_version == "v1") # no pagination or v1 OFFSET pagination

    if should_hit_repository_id_and_pushed_at_index
      base_sql = base_sql.use_index("index_pushes_on_repository_id_and_pushed_at")
    end

    results = base_sql.to_a

    has_more_records = results.size > per_page
    # Remove the extra push fetched for determining if there are more pushes to load
    results.pop if has_more_records

    if backward_pagination
      results = results.reverse
    end

    if forward_pagination
      has_previous_page = false if after.nil? # There is no previous page if we're paginating forwards and there is no `after` cursor
      has_next_page = has_more_records
    elsif backward_pagination
      has_previous_page = has_more_records
      has_next_page = false if before.nil? # There is no next page if we're paginating backwards and there is no `before` cursor
    else # old page-offset pagination
      has_previous_page = false if before.nil? && after.nil?
      has_next_page = has_more_records
    end

    case cursor_version
    when "v1"
      start_cursor = results.empty? ? "" : encode_cursor(cursor_id || results.first.id, page || 0)
      end_cursor = nil
    when "v2"
      start_cursor = results.empty? ? "" : encode_cursor_v2(results.first.id, results.first.pushed_at)
      end_cursor = results.empty? ? "" : encode_cursor_v2(results.last.id, results.last.pushed_at)
    end

    [results, has_previous_page, has_next_page, start_cursor, end_cursor]
  end

  # Fetches the last commit for every push in a list.
  def fetch_last_commits(pushes)
    current_repository.rpc.read_objects(pushes.map(&:after), :commit, true).map { |commit| Commit.new(current_repository, commit) }.map { |commit| [commit.oid, commit] }.to_h
  end

  def encode_cursor(start_id, page)
    Base64.urlsafe_encode64("v1:" + MessagePack.pack([start_id, page]), padding: false)
  end

  def encode_cursor_v2(id, pushed_at)
    # IMPORTANT: `pushed_at` column has additional precision of `datetime(6)`.
    # So when encoding the cursor, make sure to include fractional seconds!
    Base64.urlsafe_encode64("cursor:v2:" + MessagePack.pack([id, pushed_at.iso8601(6)]), padding: false)
  end

  def cursor_version
    if current_user&.feature_enabled?(:activity_view_cursor_v2)
      "v2"
    else
      "v1"
    end
  end

  def decode_cursor(cursor)
    version, cursor_id, page, cursor_timestamp = nil
    decoded = Base64.urlsafe_decode64(cursor) if cursor.present?

    if decoded&.start_with?("v1:")
      decoded = decoded[3..-1]
      cursor_id, page = MessagePack.unpack(decoded)
      version = "v1"
    elsif decoded&.start_with?("cursor:v2:")
      decoded = decoded[10..-1]
      cursor_id, cursor_timestamp = MessagePack.unpack(decoded)
      cursor_timestamp = DateTime.iso8601(cursor_timestamp)
      version = "v2"
    end

    [version, cursor_id, page, cursor_timestamp]
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
      add_csrf_token(restore_url, :post)
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
    restore_oids = current_repository.pushes.where(ref: refs_to_restore).branch_deletion_push_type.group_by(&:ref).map { |ref, pushes| [ref, pushes&.last&.before] }.to_h
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
    pushes, has_previous_page, has_next_page, start_cursor, end_cursor = fetch_pushes(**parsed_params)

    # Fetch the last commit for each push, to display in the push description
    last_commits = fetch_last_commits(pushes)

    # Fetch the last oid for deleted refs to optionally restore to
    restore_oids = current_user_can_push? ? fetch_restore_oids(pushes) : {}

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
        items: pushes.map { |push| to_json_push(push, last_commit: last_commits[push.after], restore_oid: push.deleted? && !push.ref_is_tag? ? restore_oids[push.ref] : nil) },
        has_next_page: has_next_page,
        has_previous_page: has_previous_page,
        activity_type: parsed_params[:activity_type],
        actor: to_json_pusher(parsed_params[:actor]),
        time_period: parsed_params[:time_period],
        sort: parsed_params[:sort],
        per_page: parsed_params[:per_page],
        cursor: start_cursor,
        start_cursor: cursor_version == "v2" ? start_cursor : nil,
        end_cursor: cursor_version == "v2" ? end_cursor : nil
      }
    }
  end
end
