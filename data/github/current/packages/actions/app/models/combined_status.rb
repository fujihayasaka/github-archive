# typed: true
# frozen_string_literal: true

# Represents the aggregate status of the given sha for the given repository.
class CombinedStatus
  include GitHub::Relay::GlobalIdentification

  # Public: Return an array of CombinedStatus objects for the given shas.
  # A CombinedStatus object with no statuses (#any? == false) will be
  # returned for SHAs with no status objects.
  #
  # repo - A Repository
  # shas - An Array of String SHA1s
  #
  # Returns a Hash of CombinedStatuses keyed off the sha.
  sig { params(repo: Repository, shas: T::Array[String]).returns(T::Hash[String, CombinedStatus]) }
  def self.combined_statuses_for_shas(repo, shas)
    current_by_shas = Statuses.domain.current_statuses_for_shas_group_by_sha(repository_id: repo.id, shas: shas)

    combined_statuses = {}
    shas.each do |sha|
      statuses_for_sha = current_by_shas.fetch(sha, [])
      combined_statuses[sha] = new(repo, sha, statuses: statuses_for_sha)
    end
    combined_statuses
  end

  attr_reader :sha, :repository, :platform_type_name

  # Public: Construct a new CombinedStatus.
  #
  # repo - The Repository for this status.
  # sha  - The commit SHA for this combined status
  # statuses - Optional array of Statuses to be used for this combined status
  # check_runs - Optional array of CheckRuns to be used for this combined status
  # platform_type_name - Optional String of name of the Platform type
  #                      TODO: This needs to be replaced with 1-1 relations between
  #                      Platform objects and application models. Currently, `CombinedStatus`
  #                      powers both Platform objects, `Status` and `StatusCheckRollup`.
  #
  # state - Optional precalculated rollup state
  # short_text - Optional precalculated short text (e.g. "3 / 4 checks OK")
  # Returns a CombinedStatus
  def initialize(repo, sha, statuses: nil, check_runs: nil, platform_type_name: "Status", state: nil, short_text: nil)
    raise ArgumentError, "invalid sha: #{sha}" unless sha =~ /\A[a-f0-9]{40}\z/i

    @repository          = repo
    @sha                 = sha
    @current_page        = 1
    @memoized_statuses   = statuses.to_a if statuses
    @memoized_check_runs = wrap_check_runs(check_runs.to_a) if check_runs
    @platform_type_name  = platform_type_name
    @state               = state
    @short_text          = short_text
  end

  def prefill
    async_prefill.sync
  end

  def async_prefill
    Promise.all([
      Promise.all(latest_statuses_by_context.map do |status|
        status.async_oauth_application.then do |oauth_application|
          Promise.all([
            oauth_application&.async_user,
            status.async_creator,
          ])
        end
      end),
      Promise.all(latest_check_runs_by_name.map do |check_run|
        check_run.async_check_suite.then do |check_suite|
          next unless check_suite

          Promise.all([
            check_run.async_workflow_job_run,
            check_suite.async_github_app,
            check_suite.async_workflow_run,
            check_run.async_repository
          ]).then do |_, github_app|
            next unless github_app

            github_app.async_bot.then do |bot|
              next unless bot

              bot.async_primary_avatar_path
            end
          end
        end
      end),
    ])
  end

  sig { returns(T::Array[T.any(Status, CheckRunAdapter)]) }
  def status_checks
    latest_statuses_by_context + latest_check_runs_by_name
  end

  # We have two different CombinedStatus objects.
  # The other one comes from GraphQL, and calls things `contexts`.
  # We have views that sometimes get instantiated with one type
  # of combined status, and sometimes with the other.
  # So to simplify some logic, it would help to be able
  # to use one name to refer to them. That means aliasing
  # either here or there. I don't want to dirty up the GraphQL stuff,
  # since GraphQL is our future. So here we are.
  alias_method :contexts, :status_checks

  def state
    return @state if @state
    status_check_rollup.state
  end

  def updated_at
    status_check_rollup.updated_at
  end

  def count
    status_checks.count
  end

  # Public: Returns first status if only one is reported.
  #
  # Many view paths still prefer showing a simplier UI if only one context
  # is used.
  #
  # Returns Status or nil if multiple statuses are used.
  def single_status
    if status_checks.count == 1
      status_checks.first
    else
      nil
    end
  end

  # Returns if there are any statuses at all for this commit
  #
  # Returns true or false
  def any?
    status_checks.any?
  end

  # Returns true if all contexts are successful.
  #
  # Returns true or false
  def green?
    state == "success"
  end

  # Public: Get cache key for model suitable for use as a memcache key.
  #
  # Compatible with AR::Base#cache_key format.
  #
  # Returns String.
  def cache_key
    last = status_checks.max_by(&:state_changed_at)

    ["combined_status", repository.id, sha, last.class, last&.id.to_i].join("/")
  end

  def global_id
    "#{repository.id}:#{sha}"
  end

  # Quack like WillPaginate for API responses.
  attr_reader :per_page, :current_page
  def paginate(pagination)
    @per_page = pagination[:per_page]
    @current_page = pagination[:page]
    self
  end

  def total_pages
    return 1 unless per_page
    count.fdiv(per_page).ceil
  end

  def total_entries
    count
  end

  # Returns latest statuses by context. The difference between this and
  # status_checks is that this will respect a previous call
  # to #paginate
  def statuses
    return status_checks unless per_page

    start = (current_page - 1) * per_page
    status_checks.slice(start, per_page) || []
  end

  def latest_statuses_by_context
    # We memoize this as an array, as there are a couple of situations where we
    # need to count both successful and non-successful statuses by context
    # (such as "2/4 checks okay"). Leaving this as a relation both confuses
    # code using a block (like `statuses.count { this.is.ignored }`) and would
    # require using two queries for the same sorts of counts.
    #
    # This query has no limit, but is capped to the number of contexts,
    # which is about 15 in the wild at time of writing. More discussion
    # in https://github.com/github/github/pull/40052.
    @memoized_statuses ||= Statuses::Service.current_for_shas(repository_id: repository.id, shas: sha).to_a
  end

  # If the feature flag is not enabled, then we will not return check runs
  # even if they were passed to CombinedStatus.new.
  def latest_check_runs_by_name
    @memoized_check_runs ||= wrap_check_runs(CheckRun.latest_for_sha_and_event_in_repository(sha, repository).to_a)
  end

  def async_contexts_with_no_spammy_creators
    return @async_contexts_with_no_spammy_creators if defined?(@async_contexts_with_no_spammy_creators)
    @async_contexts_with_no_spammy_creators = begin
      statuses = latest_statuses_by_context
      check_runs = latest_check_runs_by_name

      Promise.all(check_runs.map(&:async_check_suite)).then do
        Promise.all(statuses.map(&:async_creator)).then do |creators|
          spammy_creators = creators.collect { |c| c&.spammy? ? c.id : nil }.compact
          statuses = statuses.reject { |c| spammy_creators.include?(c.creator_id) }

          contexts = statuses + check_runs
          contexts.sort_by(&:sort_order)
        end
      end
    end
  end

  def short_text
    return @short_text if @short_text.present?

    contexts_with_state = status_checks.map do |c|
      [c.context, c.state.upcase]
    end
    @short_text = Statuses::ContextsHelper.new(contexts_with_state).short_text
  end

  def rollup_archive_message
    "These checks have been archived and are scheduled for deletion."
  end

  def rollup_deleted_message
    "Additional information about these checks has been deleted."
  end

  private

  def wrap_check_runs(check_runs)
    check_runs.map { |run| CombinedStatus::CheckRunAdapter.new(run) }
  end

  # In the PR view, PR timeline, and Commit view, we need to
  # aggregate the result of both Checks and Statuses.
  # To do this, we will ensure that Status and CheckRun share
  # a common interface (duck type).
  # The logic for the combination of statuses and checks lives
  # in the StatusCheckRollup.
  def status_check_rollup
    @status_check_rollup ||= StatusCheckRollup.new(status_checks: status_checks)
  end
end
