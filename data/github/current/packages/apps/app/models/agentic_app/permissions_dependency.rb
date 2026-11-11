# typed: strict
# frozen_string_literal: true

module AgenticApp
  module PermissionsDependency
    extend T::Helpers

    MINIMUM_PERMISSIONS = T.let({
      "contents"          => :write,
      "members"           => :read,
      "metadata"          => :read,
      "pull_requests"     => :write,
      "issues"            => :write,
      "discussions"       => :write,
      "workflows"         => :write,
      "actions"           => :write,
      "environments"      => :write,
      "secrets"           => :read,
      "actions_variables" => :read,
      "administration"    => :read,
      "checks"            => :read,
    }.freeze, T::Hash[String, Symbol])

    sig { params(permissions: T.nilable(T::Hash[String, Symbol])).returns(T::Hash[String, Symbol]) }
    def apply_minimum_permissions(permissions)
      permissions ||= {}

      MINIMUM_PERMISSIONS.each do |resource, minimum_action|
        assigned = permissions[resource]

        # Keep the assigned action if it already meets or exceeds the minimum.
        next if assigned && Permission::ACTION_RANKING[minimum_action] <= Permission::ACTION_RANKING[assigned]

        permissions[resource] = minimum_action
      end

      permissions
    end
  end
end
