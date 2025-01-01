# typed: true
# frozen_string_literal: true

class Repos::TransferController < AbstractRepositoryController
  include ConditionalAccessHelper
  include Repos::OwnerRepoSelectionsPayloadHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Permissions,
    ApplicationRecord::Memex,
    ApplicationRecord::Pages,
  only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  before_action :ensure_admin_access

  sig { returns(String) }
  def self.react_bundle_name
    "repo-creation"
  end

  def show
    add_csrf_token(repository_check_name_path, :post)

    tags = ["form:transfer"]
    tags << "defer_owners_list:#{current_user&.organizations.size > Repositories::CreateView::ORG_COUNT_DEFER_LIMIT}"
    payload = GitHub.dogstats.distribution_time("repos_form.payload.time", tags: tags) do
      owner_items = initial_owner_items_payload(cap_filter, T.must(current_user))
      codespaces_count = Codespace.where(repository_id: current_repository.id).count

      {
        repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
        repoCreate: Repos::ReactPayload.repo_create_payload(owner_items, cap_filter, current_user),
        pricingPath: GitHub.billing_enabled? ? pricing_path : nil,
        repoNonTransferrableReason: helpers.repo_non_transferrable_reason(current_repository),
        repositoryTransferRequestsEnabled: GitHub.repository_transfer_requests_enabled?,
        brandedPlanName: helpers.branded_plan_name(::GitHub::Plan.free),
        pluralizedCodespaces: helpers.pluralize(codespaces_count, "codespace"),
        hasPage: !!current_repository.page,
        codespaces: codespaces_count,
        ownerFreePlan: current_repository.owner.free_plan?,
        organizationDiscussion: current_repository.organization_discussion.present?,
        pendingTransfer: current_repository.pending_transfer&.target&.display_login,
        canTransferOwnership: current_repository.can_transfer_ownership?,
        hasRulesetsOrProtectedBranches: current_repository.rulesets.any? || current_repository.protected_branches.any?,
      }
    end

    add_client_feature_flag([:custom_properties_editing_redesign, :repos_limits])

    render_react_app(
      title: "Transfer repository",
      payload: payload,
      page_data: {
        send_vitals: true,
        selected_link: :repo_settings,
      },
      disable_ssr: !feature_enabled_globally_or_for_current_user?(:repos_forms_ssr),
    )
  end
end
