# typed: true
# frozen_string_literal: true

module Actions
  autoload :PolicyChecker, "actions/policy_checker"
  autoload :PolicyResolver, "actions/policy_resolver"
  autoload :PolicyUpdater, "actions/policy_updater"
  autoload :CustomImagesPolicyUpdater, "actions/custom_images_policy_updater"
  autoload :AllowedTypesUpdater, "actions/allowed_types_updater"
  autoload :Invocation, "actions/invocation"
end
