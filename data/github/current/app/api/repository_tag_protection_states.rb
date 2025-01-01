# typed: true
# frozen_string_literal: true

class Api::RepositoryTagProtectionStates < Api::App
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  get "/repositories/:repository_id/tags/protection", operation_id: "repos/list-tag-protection" do
    repo = find_repo!
    control_access :read_tag_protection, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    deliver_410!
  end

  post "/repositories/:repository_id/tags/protection", operation_id: "repos/create-tag-protection" do
    repo = find_repo!
    control_access :update_tag_protection, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    deliver_410!
  end

  delete "/repositories/:repository_id/tags/protection/:tag_protection_id", operation_id: "repos/delete-tag-protection" do
    repo = find_repo!
    control_access :update_tag_protection, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    deliver_410!
  end

  private

  def deliver_410!
    deliver_error!(410,
      message: "Tag protections have been fully deprecated. Please use tag rulesets instead.",
      documentation_url: "https://github.blog/changelog/2024-05-29-sunset-notice-tag-protections/"
    )
  end
end
