# typed: strict
# frozen_string_literal: true

class Configurations::Domain < GH::Domain::Base
  decorate_with Configsd::DevServerNotice if Rails.env.development?

  # Get resolved configuration entries for a target ownership chain
  # Currently supports Repository, User, and Business, and GitHub targets
  sig { params(ownership_chain: Configurations::RepoOwnershipChain).returns(Configurations::ResolvedConfigEntries) }
  def resolve_configs_by_target_with_owners(ownership_chain)
    Configsd::Cache::ByTarget.new([ownership_chain]).fetch do
      Configsd.client.resolve_configs_by_target_with_owners(**ownership_chain.to_h.compact)
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

    Configsd::Cache::ByTargets.new(ownership_chains).fetch_multi do |missing_chains|
      targets = missing_chains.map { |chain| chain.to_h.compact }
      resolved_entries = Configsd.client.resolve_configs_by_targets_with_owners(targets: targets)
      missing_chains.each_with_object({}) do |chain, result|
        target_type, target_id = chain.target_info
        result[chain] = resolved_entries.dig(target_type, target_id) || {}
      end
    end
  end
end
