# typed: true
# frozen_string_literal: true

class Api::RepositoryTagProtectionStates < Api::App
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  # Get the tag protection state of a repository
  get "/repositories/:repository_id/tags/protection", operation_id: "repos/list-tag-protection" do
    deprecated(
      deprecation_date: Time.new(2024, 5, 29),
      sunset_date: Time.new(2024, 8, 30),
      info_url: "https://gh.io/tag-protection-sunset",
      alternate_path_url: "/repos/{owner}/{repo}/rulesets",
    )
    repo = find_repo!
    control_access :read_tag_protection, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    check_tag_protection_brownout!(repo)
    ensure_protected_tags_available!(repo)
    tag_protection_states = RepositoryTagProtectionState.where(repository: repo)
    deliver :tag_protection_state_hash, tag_protection_states
  end

  post "/repositories/:repository_id/tags/protection", operation_id: "repos/create-tag-protection" do
    deprecated(
      deprecation_date: Time.new(2024, 5, 29),
      sunset_date: Time.new(2024, 8, 30),
      info_url: "https://gh.io/tag-protection-sunset",
      alternate_path_url: "/repos/{owner}/{repo}/rulesets",
    )
    repo = find_repo!
    control_access :update_tag_protection, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    check_tag_protection_brownout!(repo)
    ensure_protected_tags_available!(repo)
    data = receive_with_openapi
    tag_protection_state = repo.create_tag_protection_state(pattern: data["pattern"])
    deliver_error!(400) unless tag_protection_state.valid?
    deliver :tag_protection_state_hash, tag_protection_state, status: 201
  end

  delete "/repositories/:repository_id/tags/protection/:tag_protection_id", operation_id: "repos/delete-tag-protection" do
    deprecated(
      deprecation_date: Time.new(2024, 5, 29),
      sunset_date: Time.new(2024, 8, 30),
      info_url: "https://gh.io/tag-protection-sunset",
      alternate_path_url: "/repos/{owner}/{repo}/rulesets/{ruleset_id}",
    )
    repo = find_repo!
    control_access :update_tag_protection, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    check_tag_protection_brownout!(repo)
    ensure_protected_tags_available!(repo)
    tag_protection_id = int_id_param!(key: :tag_protection_id)
    tag_protection = RepositoryTagProtectionState.find_by(repository: repo, id: tag_protection_id)
    deliver_error!(404) unless tag_protection

    tag_protection.destroy
    deliver_empty status: 204
  end

  private

  def ensure_protected_tags_available!(repo)
    case repo.tag_protections_availability
    when :disabled
      deliver_error!(410,
        message: "Tag protections have been fully deprecated. Please use tag rulesets instead.",
        documentation_url: "https://github.blog/changelog/2024-05-29-sunset-notice-tag-protections/"
      )
    when :not_in_plan
      deliver_error!(403, message: "Upgrade to GitHub Pro or make this repository public to enable this feature.")
    end
  end

  # Check based on user so we aren't dependent on the repo
  # If there's a brownout, we should return this error regardless of if the repo is found or not
  # unless the repo, owner, org, enterprise is opted out
  def check_tag_protection_brownout!(repo)
    if feature_enabled_globally_or_for_user?(feature_name: :tag_protection_api_brownout) && !repo.async_scoped_feature_flag_enabled?(:repos_remove_tag_protections_opt_out).sync
      deliver_error!(410,
        message: "This is a scheduled brownout of the tag protections API. Tag protections will be fully deprecated on 2024-08-30. At that point, this API endpoint will be removed. Please use tag rulesets instead.",
        documentation_url: "https://github.blog/changelog/2024-05-29-sunset-notice-tag-protections/"
      )
    end
  end
end
