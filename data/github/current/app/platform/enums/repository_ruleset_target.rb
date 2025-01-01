# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryRulesetTarget < Platform::Enums::Base
      description "The targets supported for rulesets. NOTE: The push target is in beta and subject to change."

      value "BRANCH", "Branch", value: "branch"
      value "TAG", "Tag", value: "tag"
      value "PUSH", "Push", value: "push"
      value "MEMBER_PRIVILEGE", "Member privilege", value: "member_privilege", feature_flag: :member_privilege_rulesets
    end
  end
end
