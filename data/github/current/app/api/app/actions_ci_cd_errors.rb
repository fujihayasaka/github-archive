# typed: true
# frozen_string_literal: true

module Api::App::ActionsCiCdErrors
  ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE = "You must be an org admin or have the runners and runner groups fine-grained permission."
  ORG_ACTIONS_SECRETS_FORBIDDEN_MESSAGE = "You must be an org admin or have the actions secrets fine-grained permission."
  ORG_ACTIONS_VARIABLES_FORBIDDEN_MESSAGE = "You must be an org admin or have the actions variables fine-grained permission."
  ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE = "You must be an org admin or have the actions policies fine-grained permission."
  ORG_ACTIONS_CACHE_FORBIDDEN_MESSAGE = "Must have admin read rights to Organization."
  ORG_ACTIONS_CUSTOM_IMAGES_FORBIDDEN_MESSAGE = "You must be an org admin or have the custom images fine-grained permission."

  REPO_RUNNERS_READ_FORBIDDEN_MESSAGE = "You must have repository read permissions or have the repository runners fine-grained permission."
  REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE = "You must have repository write permissions or have the repository runners fine-grained permission."
  REPO_ACTIONS_SECRETS_READ_FORBIDDEN_MESSAGE = "You must have repository read permissions or have the repository secrets fine-grained permission."
  REPO_ACTIONS_SECRETS_WRITE_FORBIDDEN_MESSAGE = "You must have repository write permissions or have the repository secrets fine-grained permission."
  REPO_ACTIONS_VARIABLES_READ_FORBIDDEN_MESSAGE = "You must have repository read permissions or have the repository variables fine-grained permission."
  REPO_ACTIONS_VARIABLES_WRITE_FORBIDDEN_MESSAGE = "You must have repository write permissions or have the repository variables fine-grained permission."
  REPO_ACTIONS_POLICIES_READ_FORBIDDEN_MESSAGE = "You must have repository read permissions or have the repository Actions policies fine-grained permission."
  REPO_ACTIONS_POLICIES_WRITE_FORBIDDEN_MESSAGE = "You must have repository write permissions or have the repository Actions policies fine-grained permission."
end
