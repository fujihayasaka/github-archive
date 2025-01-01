# typed: true
# frozen_string_literal: true

module Api::App::ActionsCiCdErrors
  ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE = "You must be an org admin or have the runners and runner groups fine-grained permission."
  ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE = "You must be an org admin or have the actions secrets fine-grained permission."
  ORG_ACTIONS_VARIABLES_FORBIDDEN_MESSAGE = "You must be an org admin or have the actions variables fine-grained permission."
  ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE = "You must be an org admin or have the actions policies fine-grained permission."
  ORG_ACTIONS_CACHE_FORBIDDEN_MESSAGE = "Must have admin read rights to Organization."
  ORG_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE = "You must be an org admin or have the custom images fine-grained permission."
end
