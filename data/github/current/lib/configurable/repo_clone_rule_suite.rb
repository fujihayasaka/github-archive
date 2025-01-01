# typed: true
# frozen_string_literal: true

module Configurable
  module RepoCloneRuleSuite
    extend T::Helpers

    REPO_CLONE_RULE_SUITE_KEY = "repo_clone_rule_suite.id".freeze

    requires_ancestor { Repository }

    sig { params(id: Integer, actor: T.untyped).void }
    def set_repo_clone_rule_suite_id(id, actor:)
      config.set(REPO_CLONE_RULE_SUITE_KEY, id, actor)
    end

    sig { returns(T.nilable(Integer)) }
    def repo_clone_rule_suite_id
      id = config.get(REPO_CLONE_RULE_SUITE_KEY).to_i
      id != 0 ? id : nil
    end
  end
end
