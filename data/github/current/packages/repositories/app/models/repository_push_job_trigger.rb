# typed: true
# frozen_string_literal: true

class RepositoryPushJobTrigger
  include GitHub::Memoizer

  MAX_PUSH_EVENT_REF_UPDATES = 1_000

  attr_reader :repository, :author, :ref_updates, :pushed_at, :push_options, :excluded_pull_ids, :merge_method, :merge_action
  attr_reader :oauth_access_id, :sockstat_context, :quarantine_push_state, :pusher_id, :start_sha, :end_sha

  # ref_updates - An array of ref updates. Multiple ref updates may be passed in from git client callsites,
  #               HOWEVER, monolith callsites should only ever pass one ref update.
  # excluded_pull_ids - An array which, if provided, indicates PRs that have been eagerly synchronized
  #                     and can be skipped by `synchronize_requests_for_ref`.
  # merge_method - The merge method, if provided, indicates the push resulted from a programmatic PR merge.
  #                Could be :merge, :squash, or :rebase.
  # merge_action - Symbol that we use to log which type of action was taken that resulted in the merge.
  #                One of :indirect_merge, :direct_merge, :admin_override_merge, :auto_merge,
  #                :merge_queue_merge, or :api_merge_queue_merge
  # quarantine_push_state - An encoded string or nil. If this is set, we are coming from a git client callsite and
  #                         we need to look inside the quarantine repository to mark authentic commits.
  #                         However, this is not reliable for completely identifying a git client callsite,
  #                         because we'll pass nil if we want to throw away the quarantine.
  def initialize(repository, author, ref_updates, pushed_at, push_options = nil, sockstat_context = {},
    excluded_pull_ids: nil,
    merge_method: nil,
    merge_action: nil,
    quarantine_push_state: nil,
    pusher_id: nil,
    start_sha: nil,
    end_sha: nil
  )
    @repository  = repository
    @pusher_id   = pusher_id
    @author      = fetch_pusher(author, pusher_id)
    @ref_updates = ref_updates
    @pushed_at   = pushed_at.presence || Time.current
    @push_options = push_options
    @excluded_pull_ids = excluded_pull_ids
    @merge_method = merge_method
    @merge_action = merge_action
    @quarantine_push_state = quarantine_push_state

    @sockstat_context = hydrate_api_context(sockstat_context)
    @oauth_access_id = @sockstat_context.delete(:oauth_access_id)

    if start_sha.present? && end_sha.present?
      # This case is deprecated. To be deleted.
      @start_sha = start_sha
      @end_sha = end_sha
    elsif AuthenticCommits::CommitContext.has_new_commits_in_context?
      # If new commits are stored in context, it means we're coming from a monolith callsite and we
      # want to grab the related commit range from context to mark authentic commits. In this case,
      # there can only be one commit range (aka one ref update) to process at a time.
      return unless FeatureFlag.vexi.enabled?(:git_commits_via_push_job, repository, default: false)

      if ref_updates.count > 1
        GitHub.dogstats.increment("repository_push_trigger.error")
        GitHub.logger.error("RepositoryPushJobTrigger failed for #{repository.id} due to multiple ref updates from the monolith")
        # raise in test/dev for high alert signal but do not fail this path in production
        raise StandardError.new("Must be called with only one ref update from the monolith") if GitHub::AppEnvironment.test? || GitHub::AppEnvironment.development?
        return
      end

      # We ensure a single ref update above, so retrieve the one and only ref update.
      end_oid = ref_updates.first&.after_oid || nil

      if end_oid.nil?
        GitHub.dogstats.increment("repository_push_trigger.error")
        GitHub.logger.error("RepositoryPushJobTrigger failed for #{repository.id} due to a nil end_oid")
        # raise in test/dev for high alert signal but do not fail this path in production
        raise StandardError.new("Ref update is missing an ending oid") if GitHub::AppEnvironment.test? || GitHub::AppEnvironment.development?
        return
      end

      @start_sha, @end_sha = AuthenticCommits::CommitContext.pop(end_oid)
    end
  end

  def enqueue
    enqueue_repository_push_job
  end

  private

  def enqueue_repository_push_job
    log_push_event_info(
      message: "Started processing push event",
      code_function: "enqueue_repository_push_job",
      extra_data: {
        "gh.repo.path": repository.shard_path,
        "gh.actor.login": pusher,
        "gh.actor.id": pusher_id,
        "push.ref_count": ref_updates.size,
      }
    )

    non_ref_change_push_count = ref_updates.count { |ref_update| ref_update.before_oid == ref_update.after_oid }
    GitHub.dogstats.count("repository_push_trigger.non_ref_change_push.count", non_ref_change_push_count) if non_ref_change_push_count > 0

    updates = convert_ref_updates_to_repository_push_data(ref_updates)

    request_context = begin
      Hydro::EntitySerializer.request_context(GitHub.context.to_hash)
    rescue StandardError => e
      { request_id: GitHub.context[:request_id] }
    end

    total_ref_count = updates.size

    if total_ref_count == 0
      publish_hydro_event(
        ref_updates: [],
        request_context: request_context,
        total_ref_count: total_ref_count,
        ref_batch_number: 1,
        total_branch_count: 0
      )
    else
      updates.each_slice(MAX_PUSH_EVENT_REF_UPDATES).with_index do |ref_update_slice, idx|
        if !gist?
          total_branch_count = updates.count { |ref_update| ref_update[0].start_with?("refs/heads/") }

          publish_hydro_event(
            ref_updates: ref_update_slice,
            request_context: request_context,
            total_ref_count: total_ref_count,
            ref_batch_number: idx + 1,
            total_branch_count: total_branch_count
          )
        else
          GistPushJob.perform_later(repository.shard_path, pusher, ref_update_slice, pushed_at, push_options, oauth_access_id)
        end
      end
    end
  rescue => e
    GitHub.dogstats.increment("repository_push_trigger.error")
    GitHub.logger.error("RepositoryPushJobTrigger failed for #{repository.id} with error: #{e.message}")

    raise e
  end

  def publish_hydro_event(ref_updates:, request_context:, total_ref_count:, ref_batch_number:, total_branch_count:)
    payload = {
      repository_id: repository.id,
      request_context: request_context,
      ref_updates:  ref_updates.map { |ref, before, after| Hydro::EntitySerializer.push(ref: ref, before: before, after: after) },
      pushed_at: pushed_at,
      push_options: Hydro::EntitySerializer.push_options(push_options),
      oauth_access_id: oauth_access_id,
      user_programmatic_access_id: sockstat_context[:user_programmatic_access_id],
      installation_id: sockstat_context[:installation_id],
      installation_type: sockstat_context[:installation_type],
      excluded_pull_ids: excluded_pull_ids,
      merge_method: merge_method,
      merge_action: merge_action,
      pusher: pusher,
      enabled_flags: enabled_hydro_job_flags,
      path: repository.shard_path,
      total_ref_count: total_ref_count,
      ref_batch_number: ref_batch_number,
      total_branch_count: total_branch_count,
      quarantine_push_state: quarantine_push_state,
      pusher_id: pusher_id,
      start_sha: start_sha,
      end_sha: end_sha
    }

    published = T.let(nil, T.nilable(T::Boolean))

    # If we don't have a replication state header in the message, the default job behavior is to wait for replication lag on all clusters.
    # If we don't have any replication_state populated at this point, we should not wait for replication lag on *any* clusters.
    # So, we use with_static_replication_state to explicitly set the replication state to {} if it's not already set.
    # This is propagated via a hydro message header to the push jobs.
    DatabaseSelector::LastOperations.with_static_replication_state({}) do
      idempotent = false
      if repository.respond_to?(:feature_enabled_for_repo_or_owner?)
        idempotent = repository.feature_enabled_for_repo_or_owner?(:idempotent_push_events)
      else
        # For cases like Wikis that use GitHub::Unsullied::Wiki which does not have the 'feature_enabled_for_repo_or_owner?' method.
        # undefined method 'feature_enabled_for_repo_or_owner?' for an instance of GitHub::Unsullied::Wiki
        idempotent = FeatureFlag.vexi.enabled?(:idempotent_push_events, repository, default: false)
      end

      published = GitHub.aqueduct_fallback_hydro_publisher.publish(
        payload,
        schema: "github.repositories.v1.Pushed",
        partition_key: repository.id,
        idempotent: idempotent
      )
    end

    log_publish_hydro_event_finish(ref_updates: ref_updates, published: published, ref_batch_number: ref_batch_number, total_branch_count: total_branch_count)
  rescue => e
    log_publish_hydro_event_finish(ref_updates: ref_updates, published: published, ref_batch_number: ref_batch_number, total_branch_count: total_branch_count, error: e)

    raise
  end

  def log_publish_hydro_event_finish(ref_updates:, published:, ref_batch_number:, total_branch_count:, error: nil)
    extra_data = {
      "push.ref_batch_number": ref_batch_number,
      "push.branch_count": total_branch_count,
      "push.refs": ref_updates.take(10).map { |ref, before, after| "#{ref}:#{before[0..7]}->#{after[0..7]}" }.join(", "),
      "push.published": published,
    }

    if error
      extra_data[:"push.error"] = error.message
    end

    log_push_event_info(
      message: error ? "Failed publish_hydro_event" : "Finished publish_hydro_event",
      code_function: "publish_hydro_event",
      extra_data: extra_data
    )
  end

  def log_push_event_info(message:, code_function:, extra_data: {})
    GitHub.logger.info(
      message,
      {
        "code.namespace": "RepositoryPushJobTrigger",
        "code.function": code_function,
        "gh.repo.id": repository.id,
        "gh.request_id": GitHub.context[:request_id],
      }.merge(extra_data)
    )
  end

  memoize def enabled_hydro_job_flags
    Repositories::HydroPushJobFlags.enabled_for_repo(repository)
  end

  def gist?
    repository.is_a?(::Gist) || repository.is_a?(GitAuth::Gist)
  end

  def wiki?
    repository.namespace == "wiki"
  end

  def changed_ref_updates
    @changed_ref_updates ||= begin
      ref_updates.each_with_object([]) do |ref_update, updates|
        if ref_update.changed?
          updates << [ref_update.before_oid, ref_update.after_oid, Addressable::URI.encode_component(ref_update.refname, Addressable::URI::CharacterClasses::PATH)]
        end
      end
    end
  end

  def convert_ref_updates_to_repository_push_data(ref_updates)
    # Filter out pushes that do not contain a change in the ref for non-gist ref updates
    data = gist? ? ref_updates : ref_updates.select { |ref_update| ref_update.before_oid != ref_update.after_oid }
    # Ordering of ref_updates data is different for the repository push job.
    data.map { |ref_update| [ref_update.refname, ref_update.before_oid, ref_update.after_oid] }
  end

  # Internal: Attempt to find the pusher user.
  # If it's already loaded, just return the user object.
  def fetch_pusher(login_or_user, id)
    if login_or_user.is_a?(User)
      return login_or_user
    end

    ActiveRecord::Base.connected_to(role: :reading) do
      User.find_by(id: id)
    end
  end

  # Internal: The User actor who authored the commit.
  #
  # Returns a User or nil.
  def actor
    return @actor if defined?(@actor)
    author.is_a?(User) ? author : nil
  end

  # Internal: The actor who authored the commit.
  #
  # Returns a String or nil.
  def pusher
    return @pusher if defined?(@pusher)
    @pusher = case author
    when Bot
      author.display_login
    when User
      author.login
    else
      author
    end
  end

  # Internal: Attempt to send along API context we would get from
  # GitAuth when triggerd from the API itself.
  #
  # Returns a Hash.
  def hydrate_api_context(sockstat_context)
    return sockstat_context unless actor

    sockstat_context.tap do |c|
      if (oauth_access = actor.oauth_access)
        c[:oauth_access_id] = oauth_access.id
      elsif actor.can_have_granular_permissions?
        c[:installation_id]   = actor.ability_delegate.ability_id
        c[:installation_type] = actor.ability_delegate.ability_type
      elsif actor.using_auth_via_user_programmatic_access?
        c[:user_programmatic_access_id] = actor.programmatic_access.id
      end
    end
  end
end
