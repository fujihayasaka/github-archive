# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    class TargetingMapper
      sig { params(branch_name: String).returns(RepositoryRuleCondition) }
      def self.map(branch_name)
        branch_name = if branch_name == "*"
          RuleEngine::Conditions::RefNameTarget::ALL_PATTERN
        else
          "refs/heads/#{branch_name}"
        end

        RepositoryRuleCondition.new(
          target: "ref_name",
          parameters: {
            include: [branch_name],
            exclude: []
          }
        )
      end
    end
  end
end
