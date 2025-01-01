# typed: true
# frozen_string_literal: true

class GitHubModels::OrganizationAccessPoliciesController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :require_feature
  before_action :organization_admin_required
  before_action :github_models_required
  before_action :parse_json_params, only: [:create, :destroy]
  before_action :require_valid_publisher_ids
  before_action :require_valid_model_slugs

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:create, :destroy]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:show],
    optional: true

  layout "organization_settings"

  def self.react_bundle_name
    "github-models-org-settings"
  end

  def show
    add_client_feature_flag([:github_models_billing_ui])

    respond_with_react(
      title: "#{this_organization.display_login} settings · GitHub Models access policy",
      payload: AccessPolicyShowPayload.new(organization_access_policy: organization_access_policy, org: this_organization),
      page_data: {
        selected_link: :github_models_organization_access_policy,
        stafftools: stafftools_user_path(this_organization),
      },
    )
  end

  def create
    if params[:enable].to_s == "1"
      success = this_organization.enable_models_access(current_user)
      status = success ? :ok : :unprocessable_entity
    elsif params[:allow_all].to_s == "1"
      success = organization_access_policy.allow_all_models(actor: current_user)
      status = success ? :ok : :unprocessable_entity
    elsif models.empty? && publishers.empty?
      success = organization_access_policy.use_blocklist(actor: current_user)
      status = success ? :ok : :unprocessable_entity
    else
      total_publishers_allowed = organization_access_policy.allow_publishers(publishers, actor: current_user)
      total_models_allowed = organization_access_policy.allow_models(models, actor: current_user)
      total_allowed = total_models_allowed + total_publishers_allowed
      total_expected = models.size + publishers.size
      status = if total_allowed == total_expected
        :created
      elsif total_allowed.zero?
        :unprocessable_entity
      else
        :multi_status
      end
    end

    render status: status, json: organization_access_policy.to_h
  end

  def destroy
    if params[:disable].to_s == "1"
      success = this_organization.disable_models_access(current_user)
      status = success ? :ok : :unprocessable_entity
    elsif models.empty? && publishers.empty?
      success = organization_access_policy.use_allowlist(actor: current_user)
      status = success ? :ok : :unprocessable_entity
    else
      total_publishers_blocked = organization_access_policy.block_publishers(publishers, actor: current_user)
      total_models_blocked = organization_access_policy.block_models(models, actor: current_user)
      total_blocked = total_models_blocked + total_publishers_blocked
      total_expected = models.size + publishers.size
      status = if total_blocked == total_expected
        :ok
      elsif total_blocked.zero?
        :unprocessable_entity
      else
        :multi_status
      end
    end

    render status: status, json: organization_access_policy.to_h
  end

  private

  sig { returns GitHubModels::OrganizationAccessPolicy }
  memoize def organization_access_policy
    GitHubModels::OrganizationAccessPolicy.new(org: this_organization)
  end

  memoize def model_slugs
    Array.wrap(params[:model_slugs]).compact
  end

  sig { returns T::Array[GitHubModels::IModel] }
  memoize def models
    return [] if model_slugs.empty?
    GitHubModels.domain.models.find_many(slugs: model_slugs)
  end

  def require_valid_model_slugs
    unless model_slugs.size == models.size
      render status: :bad_request, json: { error: "Not all specified models exist" }
    end
    render_404 unless models.all? { |model| model.readable_by?(current_user) }
  end

  memoize def publisher_ids
    Array.wrap(params[:models_publisher_ids]).compact
  end

  sig { returns T::Array[GitHubModels::Publisher] }
  memoize def publishers
    return [] if publisher_ids.empty?
    GitHubModels::Publisher.where(id: publisher_ids).order(:id).to_a
  end

  def require_valid_publisher_ids
    unless publisher_ids.size == publishers.size
      render status: :bad_request, json: { error: "Not all specified publishers exist" }
    end
  end

  def require_feature
    render_404 unless user_feature_enabled?(:github_models_org_access_policies) || this_organization.feature_enabled?(:github_models_org_access_policies)
  end

  class AccessPolicyShowPayload < ReactPayload::Base
    def route_id
      "accessPolicyShow"
    end

    sig { params(organization_access_policy: GitHubModels::OrganizationAccessPolicy, org: ::Organization).void }
    def initialize(organization_access_policy:, org:)
      @organization_access_policy = organization_access_policy
      @org = org
    end

    def payload
      models = @organization_access_policy.all_default_models
      GitHub::PrefillAssociations.prefill_associations(models, :models_publisher)
      total_models_by_publisher_id = GitHubModels::Publisher.model_counts_by_id(models)

      publishers = models.map(&:models_publisher).compact.uniq.map do |publisher|
        total_models = total_models_by_publisher_id[publisher.id] || 0
        publisher.to_h(total_models: total_models)
      end
      publishers = publishers.sort_by { |publisher| publisher[:name].downcase }

      {
        billingEnabled: @org.models_billing_enabled?,
        orgDisplayLogin: @org.display_login,
        canEnableModelsBilling: @org.can_enable_models_billing?,
        policy: @organization_access_policy.to_h,
        publishers: publishers,
        models: models.map(&:to_organization_access_policy_show_model)
          .compact.sort_by { |model_hash| model_hash[:friendlyName].downcase },
      }
    end
  end
end
