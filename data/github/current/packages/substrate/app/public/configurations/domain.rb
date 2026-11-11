# typed: strict
# frozen_string_literal: true

class Configurations::Domain < GH::Domain::Base
  # Get resolved configuration entries for a target ownership chain
  # Currently supports Repository, User, and Business, and GitHub targets
  sig { params(ownership_chain: Configurations::RepoOwnershipChain).returns(Configurations::ResolvedConfigEntries) }
  def resolve_configs_by_target_with_owners(ownership_chain)
    Configsd::Cache::ByTargets.new([ownership_chain]).fetch do
      Configsd.client.resolve_configs_by_target_with_owners(**ownership_chain.to_h.compact)
    end || {}
  end
end
