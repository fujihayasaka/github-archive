# typed: true
# frozen_string_literal: true

class HydroRepositoriesOnPushJob < Repositories::PushHydroMessageJob
  extend T::Helpers

  use_primaries ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Collab, # Codespaces::VerifyCreationMetadataOnPush
    ApplicationRecord::RepositoriesActionsChecks, # Repository::WorkflowsDependency#persist_existing_workflows
    ApplicationRecord::IssuesPullRequests # commit_mentions

  queue_as :hydro_repositories_on_push

  retry_on_dirty_exit
  class HydroPublishError < StandardError; end
  class TwirpConnectionError < StandardError; end

  RETRYABLE_ERRORS = [
    HydroPublishError,
    TwirpConnectionError,
    GitHub::DGit::ThreepcBusyError,
    *Orchestration::RETRYABLE_ERRORS
  ]
  retry_on *RETRYABLE_ERRORS, delay: :polynomially_longer, max_retries: 8

  applies_to_wikis!

  def perform
    GitHub.dogstats.increment("hydro_repositories_on_push_job.perform")

    if !wiki?
      perform_for_repo

      default_ref_update = push_includes_default_branch?
      if default_ref_update.present?
        repository.ref_deleted(default_ref_update.ref, pusher.id) if default_ref_update.deleted?
        index_readme(default_ref_update.before, default_ref_update.after)
        index_source_code(default_ref_update.ref, default_ref_update.before, default_ref_update.after)
        index_commits
      end

      unless large_push?
        ref_updates.each do |ref_update|
          if ref_update.ref_is_branch?
            event = event(ref_update)
            notify_ref_socket_subscribers(ref_update.ref, ref_update.before, ref_update.after, event)
            GitHub.dogstats.increment("hydro_repositories_on_push_job.notify_ref_socket_subscribers")
          end

          update_websocket

          unless ref_update.deleted? || ref_update.large_push?
            commits = ref_update.commits_pushed
            notify_mentioned(commits)
            publish_commits_pushed(commits)
            record_author_count(commits)
          end
        rescue GitRPC::ObjectMissing
          # move on to next ref_update
          GitHub.dogstats.increment("repository_push.ref_update_object_missing")
        end
      end

      repository.async_backup(opts: { pushed_at: pushed_at })
      update_network_push_stats

      if (default_ref_update = push_includes_default_branch?)
        repository.instrument_initial_push if default_ref_update.before == GitHub::NULL_OID
        RepositoryCheckPreferredFilesJob.perform_later(repository.id, default_ref_update.after)
      end

      update_disk_usage
      update_language

      # Synchronize shared storage, and/or generate incremental commit-graphs.
      repository.synchronize_shared_storage

      update_pre_receive_checkout
    end
  end

  private

  def perform_for_repo
    update_repo_timestamps

    begin
      repository.adjust_default_branch
    rescue RuntimeError => boom
      if boom.to_s.include?("connection timed out")
        raise TwirpConnectionError, boom
      else
        raise
      end
    end

    # write Push records for each ref in the push
    ref_updates.each do |ref_update|
      next unless ref_update.recordable?

      push_attrs = {
        pusher: pusher,
        repository: repository,
        before: ref_update.before,
        after: ref_update.after,
        ref: ref_update.ref,
        pushed_at: pushed_at
      }

      # this is executed when the push is created
      push_proc = proc do |push|
        push.spokes_api_fail_fast_enabled = true

        push.commits = ref_update.commits_pushed unless push.large_push?
        push.set_push_type(merge_method: merge_method&.to_sym, merge_action: merge_action&.to_sym)

        # these aren't persisted but set the attribute so we can send the values to hydro
        # in the instrument_push after_commit hook.
        push.push_options = push_options

        # after_commit hooks on the Push model will also save commit_contribution
        # data, send notifications, and instrument with "push.create" additional push stats
      end

      push = T.let(nil, T.nilable(Push))
      if executions > 1
        # If we're retrying this job, we may have already created a Push, so use find_or_create_by to avoid duplicates.
        GitHub.dogstats.time("repository_push.push_save", tags: ["method:find_or_create"]) do
          push = Push.find_or_create_by!(push_attrs, &push_proc)
        end
      else
        GitHub.dogstats.time("repository_push.push_save", tags: ["method:create"]) do
          push = Push.create!(push_attrs, &push_proc)
        end
      end

      if push
        # It would be nice to do this inside the push creation proc, but we
        # need to do it here to ensure idempotent behavior.
        if repository.feature_enabled?(:dual_write_ref_updates_with_pushes)
          ref_update_attrs = {
            push: push,
            repository: repository,
            before_oid: ref_update.before,
            after_oid: ref_update.after,
            ref: ref_update.ref,
            ref_update_type: push.push_type
          }
          if executions > 1
            RefUpdate.find_or_create_by!(ref_update_attrs)
          else
            RefUpdate.create!(ref_update_attrs)
          end
        end

        push.create_check_suites if !push.deleted?
        empty = !RefPush.exists?(repository: repository)
        # upsert this record so any future pushes don't queue the sync job
        RefPush.log_push(push)
        RefPushBackfillJob.perform_later(repository.id) if empty

        push.enqueue_set_license if push.license_changed?
        push.enqueue_dependency_manifest_changed_event
        push.instrument_dependency_graph_snapshot_request

        publish_ref_update_recorded_event(push)
        publish_legacy_repository_push_event(push)
      end
    rescue GitRPC::ObjectMissing
      # move on to next ref_update
      GitHub.dogstats.increment("repository_push.ref_update_object_missing")
    end

    publish_post_receive_event
  end

  # Adapted from Repository#update_pushed_at.  Updates a repo's pushed_at
  # timestamp without triggering model callbacks and maybe also
  # refset_updated_at if it's called for by the refs in this push.
  def update_repo_timestamps
    return if repository.pushed_at && T.must(pushed_at) <= repository.pushed_at
    repository.pushed_at = pushed_at
    updates = { pushed_at: repository.pushed_at, pushed_at_usec: repository.pushed_at_usec }
    if refset_updated?
      repository.refset_updated_at = ActiveSupport::TimeWithZone.new(pushed_at.utc, pushed_at.zone)
      updates[:refset_updated_at] = pushed_at
    end
    Repository.where(id: repository.id).update_all(updates)
  end

  def refset_updated?
    ref_updates.any? do |ref_update|
      ref_update.before == GitHub::NULL_OID || ref_update.after == GitHub::NULL_OID
    end
  end

  # Returns a symbol.
  def event(ref_update)
    case
    when ref_update.created?; :create
    when ref_update.deleted?; :delete
    else :push
    end
  end

  # Record the network level pushed_at and pushed_count attributes.
  def update_network_push_stats
    repository.network&.update_push_stats(pushed_at: pushed_at, unpacked_size_in_mb: get_unpacked_size)
  end

  def get_unpacked_size
    repository.rpc.get_unpacked_size
  end

  def update_language
    return unless push_includes_default_branch?
    repository.enqueue_analyze_language_breakdown
  end

  # Update the current disk usage for this repository
  #
  # We're using the `enqueue_once_per_interval` helper from ApplicationJob to
  # prevent recalculating the disk usage too many times during many frequent
  # pushes. We will only calculate disk usage _once_ for all the pushes
  # after an hour has passed.
  def update_disk_usage
    RepositoryDiskUsageJob.enqueue_once_per_interval(args: [repository.id], interval: 60 * 60)
  end

  def update_pre_receive_checkout
    ActiveRecord::Base.connected_to(role: :reading) do
      if hook = PreReceiveHook.find_by(repository_id: repository.id)
        PreReceiveRepositoryUpdateJob.perform_later(repository.id, hook.repository_url)
      end
    end
  end

  # Iterate through the list of commits looking for modifications to the
  # repository README file. If this path is included in any of the
  # commits then enqueue an indexing job for the repository. We only care
  # about the README on the master branch.
  #
  # Returns nil.
  #
  sig { params(before: String, after: String).returns(NilClass) }
  def index_readme(before, after)
    readme_path = repository.preferred_readme ? repository.preferred_readme.name : nil
    return if readme_path.blank?

    if repository.rpc.file_changed?(readme_path, before, after)
      Search.add_to_search_index("repository", repository.id)
    end

    nil
  end

  # Update the search index with the information from this push event.
  # Files will be added, updated, or removed from the search index.
  #
  # Returns nil.
  #
  sig { params(ref: String, before: String, after: String).returns(NilClass) }
  def index_source_code(ref, before, after)
    return unless GitHub.use_elastomer_code_search?
    IndexSourceCodeJob.perform_later(repository.id, before, after, ref)
    nil
  end

  # Update the search index with the information from this push event.
  # Commits will be added or removed from the search index.
  #
  # Returns nil.
  #
  sig { returns(NilClass) }
  def index_commits
    Search.add_to_search_index("commit", repository.id)
    nil
  end

  sig { params(commits: T::Array[Commit]).void }
  def notify_mentioned(commits)
    commits.each do |commit|
      CommitMention.process(repository, commit)
    end
  end

  sig { params(commits: T::Array[Commit]).void }
  def publish_commits_pushed(commits)
    GlobalInstrumenter.instrument("repository.post_receive_commits", commits: commits)
  end

  sig { params(commits: T::Array[Commit]).void }
  def record_author_count(commits)
    commits.each do |commit|
      commit_author_count = commit.author_names&.size || 0
      GitHub.dogstats.histogram("commit.authors", commit_author_count, tags: ["action:push"])
    end
  end

  sig { returns(T.nilable(Hydro::Sink::Result)) }
  def update_websocket
    return unless pusher.present?

    data = {
      timestamp: Time.now,
      reason: "repository '#{repository.name_with_display_owner}' was pushed to by '#{pusher}'",
    }

    channel = GitHub::WebSocket::Channels.post_receive(repository, pusher)
    GitHub::WebSocket.notify_repository_channel(repository, channel, data)
  end

  sig { params(ref: String, before: String, after: String, event: Symbol).returns(T.untyped) }
  def notify_ref_socket_subscribers(ref, before, after, event)
    repository.refs.build(ref, after).
      notify_socket_subscribers(before: before,
                                after: after,
                                pusher: pusher.try(:login),
                                action: event,
                                timestamp: Time.now)
  end

  sig { params(push: Push).void }
  def publish_ref_update_recorded_event(push)
    message = {
      actor_id: pusher.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      repository_id: repository.id,
      before: push.before,
      after: push.after,
      ref: push.ref,
      push_id: push.id,
      feature_flags: [],
    }

    GitHub.aqueduct_fallback_hydro_publisher.publish(
      message,
      schema: "github.repositories.v1.RefUpdateRecorded",
      partition_key: message[:repository_id],
      raise_on_payload_too_large: true,
    )
  end

  sig { params(push: Push).returns(T.untyped) }
  def publish_legacy_repository_push_event(push)
    changed_files = push.changed_files || []
    commit_oids = (push.large_push? ? [] : push.commits.compact.map(&:oid))

    message = {
      actor: Hydro::EntitySerializer.user(pusher),
      owner: Hydro::EntitySerializer.user(repository.owner),
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      repository: Hydro::EntitySerializer.repository(repository),
      before: push.before,
      after: push.after,
      ref: push.ref.dup.force_encoding(Encoding::UTF_8),
      changed_files: changed_files.map { |f| Hydro::EntitySerializer.changed_file(f) },
      forced: push.non_fast_forward?,
      large: push.large_push?,
      commit_count: push.commits_pushed_count,
      commit_oids: commit_oids,
      branch_protection_rule: Hydro::EntitySerializer.branch_protection_rule(push.branch_protection_rule),
      feature_flags: [],
      tree_oid: Hydro::EntitySerializer.repository_tree_oid_for_branch(repository, push.branch_name),
      push_options: push_options,
      push_id: push.id,
    }

    GitHub.aqueduct_fallback_hydro_publisher.publish(
      message,
      schema: "github.v1.RepositoryPush",
      partition_key: message[:repository][:id],
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 } # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    )
  end

  sig { returns(T.untyped) }
  def publish_post_receive_event
    return unless ref_updates.any?
    updates = ref_updates.map do |update|
      {
        ref_name: update.ref.dup.force_encoding(Encoding::UTF_8),
        previous_ref_oid: update.before,
        current_ref_oid: update.after,
      }
    end

    message = {
      actor: Hydro::EntitySerializer.user(pusher),
      owner: Hydro::EntitySerializer.user(repository.owner),
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      repository: Hydro::EntitySerializer.repository(repository),
      ref_updates: Array.wrap(updates),
      feature_flags: repository.post_receive_instrumentation_feature_flags,
      pushed_at: pushed_at,
      business_id: repository.owner&.business&.id,
      business: {
        id: repository.owner&.business&.id,
        name: repository.owner&.business&.name,
      },
      languages: repository.post_receive_language_names,
    }

    GitHub.aqueduct_fallback_hydro_publisher.publish(
      message,
      schema: "github.v1.PostReceive",
      partition_key: message[:repository][:id],
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 } # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    )
  end
end
