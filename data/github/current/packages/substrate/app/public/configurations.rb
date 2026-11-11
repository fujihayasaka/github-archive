# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Configurations
  extend GH::Domain::Registration

  register_domain Configurations::Domain

  class TargetType < T::Enum
    enums do
      Repository = new("Repository")
      User = new("User")
      Business = new("Business")
      MemexProject = new("MemexProject")
      Global = new("Global")
    end
  end

  ResolvedConfigEntries = T.type_alias { T::Hash[String, Configs::Entry] }

  # A target chain for memex project configurations.
  #
  # Resolution order is project -> owner -> global. Reads walk the chain
  # returning the first non-nil value; writes and deletes target the
  # most-specific tier set on the target.
  #
  # Memex configurations are not cached by configsd, so this object is used
  # only for direct DB reads/writes through `Configurations.domain`.
  MemexTarget = Data.define(:project_id, :owner_id) do
    sig { params(project_id: T.nilable(Integer), owner_id: T.nilable(Integer)).void }
    def initialize(project_id: nil, owner_id: nil)
      super(project_id: project_id, owner_id: owner_id)
    end

    sig { returns([String, Integer]) }
    def target_info
      if project_id
        ["MemexProject", project_id]
      elsif owner_id
        ["User", owner_id]
      else
        ["global", 0]
      end
    end
  end

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
