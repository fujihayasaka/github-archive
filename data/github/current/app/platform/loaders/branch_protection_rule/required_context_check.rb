# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module BranchProtectionRule
      class RequiredContextCheck < Platform::Loader
        def self.load(protected_branch_id, context)
          self.for(protected_branch_id).load(context)
        end

        def self.load_all(protected_branch_id, contexts)
          Promise.all(contexts.map { |context| load(protected_branch_id, context) })
        end

        def initialize(protected_branch_id)
          @protected_branch_id = protected_branch_id
        end

        def fetch(contexts)
          scope = RequiredStatusCheck.where(protected_branch_id: @protected_branch_id, context: contexts)

          result = scope.pluck(:context).map { |context| [context, true] }.to_h
          result.default = false
          result
        end
      end
    end
  end
end
