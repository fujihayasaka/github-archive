# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module BranchProtectionRule
      class MatchesAndConflicts < Platform::Loader
        def self.load(repository, branch_protection_rule)
          repository.async_network.then do
            self.for(repository).load(branch_protection_rule.id)
          end
        end

        def initialize(repository)
          @repository = repository
        end

        def fetch(branch_protection_rule_ids)
          wildcard_protected_branches, exact_protected_branches = @repository.protected_branches.order(:id).partition(&:wildcard_rule?)

          result = Hash.new { |hash, key| hash[key] = { matches: [], conflicts: [] } }
          refname_to_protected_branch = Hash.new { |hash, key| hash[key] = [] }

          ref_promises = exact_protected_branches.map do |protected_branch|
            @repository.heads.async_find(protected_branch.name).then do |ref|
              next unless ref
              result[protected_branch.id][:matches] << ref
              refname_to_protected_branch[ref.name] = protected_branch
            end
          end

          Promise.all(ref_promises).sync

          unless @repository.heads.size > ProtectedBranch::MAX_BRANCHES_TO_CALCULATE_WILDCARD_MATCHES
            wildcard_protected_branches.each do |protected_branch|
              @repository.heads.each do |ref|
                if protected_branch.matches?(ref.name)
                  # Conflicts do not exist if multi-policy evaluation is enabled
                  if refname_to_protected_branch.key?(ref.name)
                    result[protected_branch.id][:conflicts] << { ref: ref, conflicting_protected_branch: refname_to_protected_branch[ref.name] }
                  else
                    refname_to_protected_branch[ref.name] = protected_branch
                    result[protected_branch.id][:matches] << ref
                  end
                end
              end
            end
          end
          result
        end
      end
    end
  end
end
