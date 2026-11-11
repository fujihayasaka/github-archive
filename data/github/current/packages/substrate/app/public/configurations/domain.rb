# typed: strict
# frozen_string_literal: true

class Configurations::Domain < GH::Domain::Base
  include GH::Domain::DestroyMethods

  decorate_with Configsd::DevServerNotice if Rails.env.development?

  MAX_BATCH_SIZE = 1_000

  # Delete a configuration entry, destroying it and invalidating the configsd cache.
  #
  # target - A Configurable target that owns the entry
  # name   - String entry name to delete
  # deleter - User removing the value (optional, for audit instrumentation)
  #
  # Returns true if the entry was deleted, false if not found.
  sig do
    params(
      target: Configurable,
      name: String,
      deleter: T.nilable(User),
    ).returns(T::Boolean)
  end
  def delete_entry(target, name:, deleter: nil)
    entry = Configuration::Entry.find_by(
      name: name,
      target_type: target.configuration_entry_type,
      target_id: target.configuration_entry_id,
    )
    return false unless entry

    destroy_entry(entry, target: target, deleter: deleter)
  end

  # Called by DestroyDependentRecordsJob when use_domain is enabled.
  # The target is already destroyed at this point, so we skip cache invalidation.
  sig { override.params(record: ActiveRecord::Base).returns(T::Boolean) }
  def background_destroy(record)
    entry = T.cast(record, Configuration::Entry)
    destroy_entry(entry, target: nil, deleter: nil)
  end

  # Called by DeleteDependentRecordsJob when use_domain is enabled.
  sig { override.params(ids: T::Array[T.any(Integer, String)]).returns(Integer) }
  def background_delete(ids)
    Configuration::Entry.where(id: ids).delete_all
  end

  # Get resolved configuration entries for a target ownership chain
  # Currently supports Repository, User, and Business, and GitHub targets
  sig { params(ownership_chain: Configurations::RepoOwnershipChain).returns(Configurations::ResolvedConfigEntries) }
  def resolve_configs_by_target_with_owners(ownership_chain)
    Configsd::Cache::ByTarget.new([ownership_chain]).fetch do
      Configsd.client.resolve_configs_by_target(**ownership_chain.to_h.compact)
    end || {}
  end

  # Get resolved configuration entries for multiple target ownership chains.
  # Returns a hash keyed by RepoOwnershipChain, whose values are hashes of config_name -> Configs::Entry.
  sig do
    params(ownership_chains: T::Array[Configurations::RepoOwnershipChain])
      .returns(T::Hash[Configurations::RepoOwnershipChain, T.nilable(T::Hash[String, Configs::Entry])])
  end
  def resolve_configs_by_targets_with_owners(ownership_chains)
    return {} if ownership_chains.empty?

    if GH.feature_flag_enabled?(:configsd_preload_batching)
      ownership_chains.each_slice(MAX_BATCH_SIZE).each_with_object({}) do |chains, result|
        result.merge!(_resolve_configs_by_targets(chains))
      end
    else
      _resolve_configs_by_targets(ownership_chains)
    end
  end

  # Resolve a single config name for targets of a given type.
  # Returns a hash from target_id to value. Targets where the name
  # is not found are omitted from the result.
  sig do
    params(
      target_type: Configurations::TargetType,
      target_ids: T::Array[Integer],
      name: String
    ).returns(T::Hash[Integer, String])
  end
  def resolve_values_for_name_and_type(target_type:, target_ids:, name:)
    return {} if target_ids.empty?

    Configuration::Entry.targeting_type(target_type.serialize).for_target_id(target_ids).named(name)
      .pluck(:target_id, :value)
      .to_h
  end

  # Resolve a single config name for a single target.
  # Returns the value if found, nil otherwise.
  sig { params(target: Configs::Target, name: String).returns(T.nilable(String)) }
  def resolve_value_for_name(target:, name:)
    target_type, target_id = target_type_and_id(target)
    resolve_values_for_name_and_type(target_type: target_type, target_ids: [target_id], name: name)[target_id]
  end

  # Return the subset of target_ids that have the given config name set to "true".
  sig do
    params(
      target_type: Configurations::TargetType,
      target_ids: T::Array[Integer],
      name: String
    ).returns(T::Array[Integer])
  end
  def target_ids_with_true_value(target_type:, target_ids:, name:)
    return [] if target_ids.empty?

    Configuration::Entry.targeting_type(target_type.serialize).for_target_id(target_ids).named(name)
      .with_true_value
      .pluck(:target_id)
  end


  TARGET_IDS_LIMIT = 10_000

  # Scan all targets of a given type for which the config is set to "true".
  # Returns a tuple of [target_ids, truncated] where truncated indicates whether
  # the result set exceeded the 10,000 limit.
  sig do
    params(
      target_type: Configurations::TargetType,
      name: String
    ).returns([T::Array[Integer], T::Boolean])
  end
  def all_target_ids_with_true_value(target_type:, name:)
    results = Configuration::Entry.targeting_type(target_type.serialize).named(name).with_true_value
      .limit(TARGET_IDS_LIMIT + 1).pluck(:target_id)
    truncated = results.length > TARGET_IDS_LIMIT
    [truncated ? results.first(TARGET_IDS_LIMIT) : results, truncated]
  end

  # Set a configuration value for a given target and key.
  # Creates or updates the entry (upsert semantics).
  #
  # Returns true if the configuration changed, false if it was a no-op.
  sig do
    params(
      ownership_chain: Configurations::RepoOwnershipChain,
      name: String,
      value: String,
      updater: T.nilable(User),
      final: T::Boolean
    ).returns(T::Boolean).
    checked(:always).
    on_failure(:raise)
  end
  def set_value(ownership_chain:, name:, value:, updater:, final: false)
    Configuration::Entry.with_write do
      target_type, target_id = entry_target_from_chain(ownership_chain)

      entry = Configuration::Entry.find_or_initialize_by(
        target_type: target_type,
        target_id: target_id,
        name: name
      )

      entry.final = final
      entry.value = value
      entry.updater = updater

      unless entry.value_attributes_changed?
        return false
      end

      begin
        entry.save!
        invalidate_configsd_cache(ownership_chain, "set")
      rescue ActiveRecord::RecordNotUnique
        existing_value = Configuration::Entry
          .where(target_type: target_type, target_id: target_id, name: name)
          .pick(:value)

        if existing_value == value
          return false
        else
          raise Configuration::ConflictingRecordError.new(setting_name: name)
        end
      end

      true
    end
  end

  # Bang version of set_value — raises if the write was a no-op (value unchanged).
  sig do
    params(
      ownership_chain: Configurations::RepoOwnershipChain,
      name: String,
      value: String,
      updater: T.nilable(User),
      final: T::Boolean
    ).void.
    checked(:always).
    on_failure(:raise)
  end
  def set_value!(ownership_chain:, name:, value:, updater:, final: false)
    unless set_value(ownership_chain: ownership_chain, name: name, value: value, updater: updater, final: final)
      raise Configuration::ConflictingRecordError.new(setting_name: name)
    end
  end

  # Memex projects are disjoint from the repository/owner/business/global
  # ownership chain, so they have their own dedicated read/write/delete
  # methods rather than overloads of the chain-keyed APIs above. Configsd
  # has no ownership-chain RPC for memex projects, so these methods read and
  # write `Configuration::Entry` directly without configsd cache invalidation.
  #
  # The chain is project -> owner -> global. Reads walk the chain in priority
  # order; writes and deletes target the most-specific tier present on the
  # supplied `MemexTarget`.
  #
  # The only config name used in this chain is
  # "memex_project_organization_wide_role", so it is hardcoded here.

  MEMEX_CONFIG_NAME = "memex_project_organization_wide_role"

  # Resolve the memex org-wide role for a target, walking the chain from
  # most-specific (project) to least-specific (global). Returns the first
  # non-nil value found, or nil if none are set.
  #
  # Fetches all candidate tiers in a single query ordered by priority,
  # then returns the highest-priority (most-specific) value.
  sig { params(memex_target: Configurations::MemexTarget).returns(T.nilable(String)) }
  def resolve_value_for_memex_target(memex_target:)
    candidates = T.let([], T::Array[[String, Integer]])
    candidates << ["MemexProject", memex_target.project_id] if memex_target.project_id
    candidates << ["User", memex_target.owner_id] if memex_target.owner_id
    candidates << ["global", 0]

    target_conditions = Arel::Nodes::Grouping.new(
      Arel::Nodes::Or.new(
        candidates.map do |type, id|
          Arel.sql("(target_type = :type AND target_id = :id)", type: type, id: id)
        end
      )
    )

    Configuration::Entry
      .where(target_conditions)
      .named(MEMEX_CONFIG_NAME)
      .order(Arel.sql(<<~SQL))
        CASE target_type
        WHEN 'global'       THEN 3
        WHEN 'User'         THEN 2
        WHEN 'MemexProject' THEN 1
        END ASC
      SQL
      .pick(:value)
  end

  # Set the memex org-wide role at the most-specific tier present on the target.
  # Returns true if the configuration changed, false if it was a no-op.
  sig do
    params(
      memex_target: Configurations::MemexTarget,
      value: String,
      updater: User,
      final: T::Boolean,
    ).returns(T::Boolean)
  end
  def set_memex_target_value(memex_target:, value:, updater:, final: false)
    target_type, target_id = memex_target.target_info

    entry = Configuration::Entry.find_or_initialize_by(
      target_type: target_type,
      target_id: target_id,
      name: MEMEX_CONFIG_NAME,
    )

    entry.final = final
    entry.value = value
    entry.updater = updater

    return false unless entry.value_attributes_changed?

    begin
      entry.save!
    rescue ActiveRecord::RecordNotUnique
      existing_value = Configuration::Entry
        .where(target_type: target_type, target_id: target_id, name: MEMEX_CONFIG_NAME)
        .pick(:value)

      if existing_value == value
        return false
      else
        raise Configuration::ConflictingRecordError.new(setting_name: MEMEX_CONFIG_NAME)
      end
    end

    true
  end

  # Delete the memex org-wide role entry at the most-specific tier present on
  # the target. Returns true if the entry was deleted, false if not found.
  sig do
    params(
      memex_target: Configurations::MemexTarget,
      deleter: T.nilable(User),
    ).returns(T::Boolean)
  end
  def delete_memex_target_entry(memex_target:, deleter: nil)
    target_type, target_id = memex_target.target_info

    entry = Configuration::Entry.find_by(
      target_type: target_type,
      target_id: target_id,
      name: MEMEX_CONFIG_NAME,
    )
    return false unless entry

    entry.destroyer = deleter
    entry.destroy!
    true
  end

  private

  # temporary method extraction to make feature flag diff clean and readable
  sig do
    params(ownership_chains: T::Array[Configurations::RepoOwnershipChain])
      .returns(T::Hash[Configurations::RepoOwnershipChain, T.nilable(T::Hash[String, Configs::Entry])])
  end
  def _resolve_configs_by_targets(ownership_chains)
    Configsd::Cache::ByTargets.new(ownership_chains).fetch_multi do |missing_chains|
      targets = missing_chains.map { |chain| chain.to_h.compact }
      resolved_entries = Configsd.client.resolve_configs_by_targets(targets: targets)
      missing_chains.each_with_object({}) do |chain, result|
        target_type, target_id = chain.target_info
        result[chain] = resolved_entries.dig(target_type, target_id) || {}
      end
    end
  end

  # Shared destroy path for both delete_entry and background_destroy.
  # When target is provided, uses destroy! and invalidates configsd cache.
  # When target is nil (background destroy), uses soft destroy (target already gone).
  sig do
    params(
      entry: Configuration::Entry,
      target: T.nilable(Configurable),
      deleter: T.nilable(User),
    ).returns(T::Boolean)
  end
  def destroy_entry(entry, target:, deleter:)
    entry.destroyer = deleter

    if target
      entry.destroy!
      targets = [*target.async_configuration_owners.sync, target].compact.uniq
      invalidate_configsd_cache(Configurations::RepoOwnershipChain.from_targets(targets), "delete")
      true
    else
      !!entry.destroy
    end
  end

  sig { params(ownership_chain: Configurations::RepoOwnershipChain, event: T.nilable(String)).void }
  def invalidate_configsd_cache(ownership_chain, event = nil)
    return unless GH.feature_flag_enabled?(:remote_cache_configs_invalidate)

    Configsd.invalidate_cache_for(ownership_chain, event)
  end

  # Derive the most-specific target_type and target_id from an ownership chain.
  # Uses the chain's target_info but maps "Global" to the DB's lowercase "global".
  sig { params(chain: Configurations::RepoOwnershipChain).returns([String, Integer]) }
  def entry_target_from_chain(chain)
    type, id = chain.target_info
    type = "global" if type == Configsd::EntryType::GLOBAL
    [type, id]
  end

  sig { params(target: Configs::Target).returns([Configurations::TargetType, Integer]) }
  def target_type_and_id(target)
    if target.repo_id && target.repo_id != 0
      [Configurations::TargetType::Repository, target.repo_id]
    elsif target.owner_id && target.owner_id != 0
      [Configurations::TargetType::User, target.owner_id]
    elsif target.business_id && target.business_id != 0
      [Configurations::TargetType::Business, target.business_id]
    else
      [Configurations::TargetType::Global, 0]
    end
  end
end
