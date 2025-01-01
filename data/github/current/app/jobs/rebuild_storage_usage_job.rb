# typed: true
# frozen_string_literal: true

require "github/sql/readonly"

class RebuildStorageUsageJob < ApplicationJob
  queue_as :rebuild_storage_usage
  retry_on_dirty_exit

  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  # user_id - ID of the user or org account responsible for this activity.
  # options:
  #   "asset_type" - String asset type matching a key in Asset::Types.
  #   "actor_ids"  - Optional Array of IDs of users
  #   "key_ids"    - Optional Array of IDs of deploy keys
  #   "notify"     - Boolean. Default to false for backwards compat.
  #   "manual"     - Boolean specifying a manual run for support reasons.
  #                  Sends metrics and rebuilds all Asset::ActorStatus
  #                  records for the given owner.
  def perform(user_id, options = {})
    @user_id = user_id.to_i
    @asset_type = options["asset_type"].blank? ? :lfs : options["asset_type"].to_sym
    @notify = !!options["notify"]
    @actor_ids = Array(options["actor_ids"]).map(&:to_i).delete_if { |i| i < 0 }
    @key_ids = Array(options["key_ids"]).map(&:to_i).delete_if { |i| i < 0 }
    @manual_run = !!options["manual"]
    @stat_tags = ["type:#{@asset_type}", "run_source:#{@manual_run ? :manual : :job}"]
    perform!
  end

  def perform!
    if !(user && status)
      GitHub.dogstats.increment("s3_usage.rebuild.skip", tags: @stat_tags)
      return
    end

    GitHub.dogstats.increment("s3_usage.rebuild.start", tags: @stat_tags)
    start = Time.now
    enabled = status.owner_feature_enabled?
    state = status.notified_state

    with_write do
      status.rebuild(skip_notify: !@notify)
      user.enable_git_lfs(user) if status.active?
    end

    if @actor_ids.present? || @key_ids.present?
      update_actor_statuses(@actor_ids.to_set, @key_ids.to_set)
    elsif @manual_run
      update_all_actor_statuses
    end
  ensure
    if start
      ms = ((Time.now.to_f - start.to_f) * 1000).round
      GitHub.dogstats.distribution("s3_usage.rebuild.dist.run", ms, tags: @stat_tags)
    end
    if state
      GitHub::Logger.log({
        job: self.class.to_s,
        owner: user.to_s,
        owner_id: @user_id,
        before_state: state.to_s,
        after_state: status.notified_state.to_s,
        before_enabled: enabled,
        after_enabled: status.owner_feature_enabled?,
        notified: @notify,
      })
    end
  end

  def update_actor_statuses(actor_ids, key_ids)
    return if actor_ids.blank? && key_ids.blank?

    # Automatically handle duplicate items.
    actor_ids = actor_ids.to_set
    key_ids = key_ids.to_set
    users = User.where(id: actor_ids).all.index_by(&:id)
    keys = PublicKey.where(id: key_ids).all.index_by(&:id)
    actors =  actor_ids.map { |id| [id, 0] }.to_set
    actors += key_ids.map { |id| [0, id] }.to_set

    # Make sure that our lookup of statuses below has neither set empty, or
    # we'll look up no records.
    actor_ids << 0
    key_ids << 0

    # bulk load actor status records for given actor ids
    statuses = Asset::ActorStatus.where(
      asset_type: Asset::ActorStatus.asset_types[@asset_type],
      owner_id: @user_id,
      actor_id: actor_ids,
      key_id: key_ids,
    ).all.index_by { |s| [s.actor_id, s.key_id] }

    # update each actor's asset status
    actors.each do |(actor_id, key_id)|
      # skip bad user ids. 0 == anonymous
      next unless actor_id.zero? || users[actor_id]
      next unless key_id.zero? || keys[key_id]
      # Don't create records where both are nonzero, since that can't occur.
      next unless actor_id.zero? || key_id.zero?

      Asset::ActorStatus.throttle_writes do
        status = statuses[[actor_id, key_id]] || Asset::ActorStatus.new(asset_type: @asset_type, owner_id: @user_id, actor_id: actor_id, key_id: key_id)
        status.rebuild
      end
    end
  end

  def update_all_actor_statuses
    scope = Asset::ActorStatus.select(:id, :actor_id, :key_id)
      .where(owner_id: @user_id)
      .where(asset_type: @asset_type)

    iterator = GitHub::QueryBatching::ScopeIterator.new(scope, batch_size: 100)
      .pluck(:id, :actor_id, :key_id)

    GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
      pairs = rows.map { |row| [row[1], row[2]] }
      user_ids = pairs.map { |(user, _)| user }.uniq
      key_ids  = pairs.map { |(_, key)| key }.uniq
      update_actor_statuses(user_ids, key_ids)
    end
  end

  def user
    @user ||= User.where(id: @user_id).first
  end

  def status
    @status ||= begin
      Asset::Status.build_for_owner(:lfs, @user_id)
      user.asset_status
    end
  end
end
