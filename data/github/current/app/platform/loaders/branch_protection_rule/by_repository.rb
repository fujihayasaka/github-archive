# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module BranchProtectionRule
      class ByRepository < Platform::Loader
        def self.load(repository)
          self.for.load(repository)
        end

        def self.load_many(repositories)
          self.for.load_many(repositories)
        end

        def fetch(repositories)
          protected_branches = ProtectedBranch.where(repository_id: repositories.map(&:id))
          if protected_branches.all?(&:unmigrated?)
            GitHub::PrefillAssociations.prefill_associations(protected_branches, [:repository, :merge_queue], available_records: repositories)
          else
            GitHub::PrefillAssociations.prefill_associations(protected_branches, [:repository, :merge_queue, :rule_configurations], available_records: repositories)
          end

          pb_by_repo = protected_branches.group_by(&:repository_id)
          repositories.each_with_object({}) do |repository, by_repository|
            by_repository[repository] = pb_by_repo[repository.id] || []
          end
        end
      end
    end
  end
end
