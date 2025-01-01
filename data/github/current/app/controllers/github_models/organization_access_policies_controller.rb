# typed: true
# frozen_string_literal: true

class GitHubModels::OrganizationAccessPoliciesController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

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
    respond_with_react(
      title: "#{this_organization.display_login} settings · GitHub Models access policy",
      payload: AccessPolicyShowPayload.new(
        organization_access_policy: organization_access_policy,
        org: this_organization,
        current_user: current_user
      ),
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
    elsif models.empty? && publishers.empty? && custom_keys.empty?
      success = organization_access_policy.use_blocklist(actor: current_user)
      status = success ? :ok : :unprocessable_entity
    else
      total_publishers_allowed = organization_access_policy.allow_publishers(publishers, actor: current_user)
      total_custom_keys_allowed = organization_access_policy.allow_custom_keys(custom_keys, actor: current_user)
      total_models_allowed = organization_access_policy.allow_models(models, actor: current_user)
      total_allowed = total_models_allowed + total_publishers_allowed + total_custom_keys_allowed
      total_expected = models.size + publishers.size + custom_keys.size
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
    elsif models.empty? && publishers.empty? && custom_keys.empty?
      success = organization_access_policy.use_allowlist(actor: current_user)
      status = success ? :ok : :unprocessable_entity
    else
      total_publishers_blocked = organization_access_policy.block_publishers(publishers, actor: current_user)
      total_custom_keys_blocked = organization_access_policy.block_custom_keys(custom_keys, actor: current_user)
      total_models_blocked = organization_access_policy.block_models(models, actor: current_user)
      total_blocked = total_models_blocked + total_publishers_blocked + total_custom_keys_blocked
      total_expected = models.size + publishers.size + custom_keys.size
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

  sig { returns T::Array[String] }
  memoize def default_model_slugs
    Array.wrap(params[:model_slugs]).compact
  end

  sig { returns T::Array[Integer] }
  memoize def custom_model_ids
    Array.wrap(params[:custom_model_ids]).compact.map(&:to_i)
  end

  sig { returns T::Array[DefaultAndCustomModels::IModel] }
  memoize def models
    result = T.let([], T::Array[DefaultAndCustomModels::IModel])
    if custom_model_ids.any?
      result = result.concat(ModelsByok::CustomModel.find_many(custom_model_ids, org: this_organization))
    end
    if default_model_slugs.any?
      result = result.concat(GitHubModels.domain.models.find_many(slugs: default_model_slugs))
    end
    result
  end

  def require_valid_model_slugs
    unless default_model_slugs.size + custom_model_ids.size == models.size
      render status: :bad_request, json: { error: "Not all specified models exist" }
    end
    render_404 unless models.all? { |model| model.readable_by?(current_user) }
  end

  sig { returns T::Array[Integer] }
  memoize def publisher_ids
    Array.wrap(params[:models_publisher_ids]).compact.map(&:to_i)
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

  sig { returns T::Array[Integer] }
  memoize def custom_key_ids
    Array.wrap(params[:custom_key_ids]).compact.map(&:to_i)
  end

  sig { returns T::Array[ModelsByok::CustomKey] }
  memoize def custom_keys
    return [] if custom_key_ids.empty?
    this_organization.models_custom_keys.where(id: custom_key_ids).order(:id).to_a
  end

  def require_valid_custom_key_ids
    unless custom_key_ids.size == custom_keys.size
      render status: :bad_request, json: { error: "Not all specified custom keys exist" }
    end
  end

  class AccessPolicyShowPayload < ReactPayload::Base
    include GitHub::Memoizer

    def route_id
      "accessPolicyShow"
    end

    sig do
      params(
        organization_access_policy: GitHubModels::OrganizationAccessPolicy,
        org: ::Organization,
        current_user: User
      ).void
    end
    def initialize(organization_access_policy:, org:, current_user:)
      @organization_access_policy = organization_access_policy
      @org = org
      @current_user = current_user
    end

    def payload
      {
        billingEnabled: @org.models_billing_enabled?,
        customKeys: custom_keys,
        orgDisplayLogin: @org.display_login,
        canEnableModelsBilling: @org.can_enable_models_billing?,
        businessBillingEnabled: @org.business&.models_billing_enabled?,
        isBusinessAdmin: @org.business.present? && T.must(@org.business).adminable_by?(@current_user),
        businessSlug: @org.business&.slug,
        hideBilling: @org.business ? !T.must(@org.business).can_show_models_billing? : !@org.can_show_models_billing?,
        policy: @organization_access_policy.to_h,
        publishers: publishers,
        models: models,
        paymentMethodRequired: @org.business.nil? && @org.payment_method_required? && !@org.models_billing_disabled_by_non_payment_method_reason?,
        invoiced: @org.business.nil? && @org.invoiced?,
        legacy: @org.billable_owner.plan.legacy?,
      }
    end

    private

    sig do
      returns T::Array[T.any(ModelsByok::Types::CustomModel, GitHubModels::Types::OrganizationAccessPolicyShowModel)]
    end
    def models
      sorted_custom_model_hashes = custom_models.map(&:to_h)
      sorted_default_model_hashes = default_models.map(&:to_organization_access_policy_show_model).compact
        # Re-sort by friendly name instead of slug since that's how we'll display them in the UI:
        .sort_by { |model_hash| model_hash[:friendlyName].downcase }
      sorted_custom_model_hashes + sorted_default_model_hashes
    end

    # Private: Returns a list of default models within the organization, whether the policy allows their use or not,
    # sorted by slug.
    sig { returns T::Array[GitHubModels::IModel] }
    memoize def default_models
      result = @organization_access_policy.all_default_models
      GitHub::PrefillAssociations.prefill_associations(result, :models_publisher)
      result
    end

    # Private: Returns a list of custom models within the organization, whether the policy allows their use or not,
    # sorted by custom key name and then by model name.
    sig { returns T::Array[ModelsByok::CustomModel] }
    memoize def custom_models
      result = @organization_access_policy.all_custom_models
      GitHub::PrefillAssociations.prefill_associations(result, :custom_key)
      result
    end

    sig { returns T::Array[GitHubModels::Types::Publisher] }
    def publishers
      total_models_by_publisher_id = GitHubModels::Publisher.model_counts_by_id(default_models)
      sorted_publishers = default_models.map(&:models_publisher).compact.uniq
        .sort_by { |publisher| publisher.display_name.downcase }
      sorted_publishers.map do |publisher|
        total_models = total_models_by_publisher_id[publisher.id] || 0
        publisher.to_h(total_models: total_models)
      end
    end

    sig { returns T::Array[ModelsByok::Types::CustomKey] }
    def custom_keys
      total_models_by_custom_key_id = ModelsByok::CustomKey.model_counts_by_id(custom_models)
      custom_models.map(&:custom_key).compact.uniq.map do |custom_key|
        total_models = total_models_by_custom_key_id[custom_key.id] || 0
        custom_key.to_h(total_models: total_models)
      end
    end
  end
end
