# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Configurations
  extend GH::Domain::Registration

  register_domain Configurations::Domain

  ResolvedConfigEntries = T.type_alias { T::Hash[String, Configs::Entry] }
  RepoOwnershipChain = Data.define(:repo_id, :owner_id, :business_id) do
    sig { params(targets: T::Array[Configurable]).returns(RepoOwnershipChain) }
    def self.from_targets(targets)
      new(
        repo_id: targets.find { |t| t.configuration_entry_type == "Repository" }&.configuration_entry_id,
        owner_id: targets.find { |t| t.configuration_entry_type == "User" }&.configuration_entry_id,
        business_id: targets.find { |t| t.configuration_entry_type == "Business" }&.configuration_entry_id,
      )
    end
  end
end
