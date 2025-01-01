# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module BranchProtectionRule
      class ByBranchName < Platform::Loader
        def self.load(repository, branch_name, return_all_matches: false)
          self.for(repository, return_all_matches).load(branch_name)
        end

        def self.load_many(repository, branch_names, return_all_matches: false)
          self.for(repository, return_all_matches).load_many(branch_names)
        end

        def initialize(repository, return_all_matches = false)
          @repository = repository
          @return_all_matches = return_all_matches
        end

        def fetch(branch_names)
          protected_branches = ProtectedBranch.where(repository_id: @repository.id).includes(:merge_queue)

          GitHub::PrefillAssociations.prefill_associations(protected_branches, :repository, available_records: [@repository])

          ordered_protected_branches = protected_branches.sort_by do |protected_branch|
            [protected_branch.wildcard_rule? ? 1 : 0, protected_branch.id]
          end

          branch_names.map do |branch_name|
            if @return_all_matches
              [branch_name, ordered_protected_branches.filter { |pb| pb.matches?(branch_name.to_s) }]
            else
              matching_protected_branch = ordered_protected_branches.find do |protected_branch|
                protected_branch.matches?(branch_name.to_s)
              end
              [branch_name, matching_protected_branch]
            end
          end.to_h
        end
      end
    end
  end
end
