# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain

    if (Rails.env.test? && ENV["RUBY_NEXT"] == "1") || Rails.env.development? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      require_relative "./rule_insights_from_repositories_pushes"
    else
      require_relative "./rule_insights_from_repositories"
    end

    class RuleInsights
      T.unsafe(self).abstract_class = true
    end
  end
end
