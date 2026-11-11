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
        repo_id: targets.find { |t| t.configuration_entry_type == Configsd::EntryType::REPOSITORY }&.configuration_entry_id,
        owner_id: targets.find { |t| t.configuration_entry_type == Configsd::EntryType::USER }&.configuration_entry_id,
        business_id: targets.find { |t| t.configuration_entry_type == Configsd::EntryType::BUSINESS }&.configuration_entry_id,
      )
    end

    def target_info
      if repo_id
        [Configsd::EntryType::REPOSITORY, repo_id]
      elsif owner_id
        [Configsd::EntryType::USER, owner_id]
      elsif business_id
        [Configsd::EntryType::BUSINESS, business_id]
      else
        [Configsd::EntryType::GLOBAL, 0]
      end
    end
  end
end
