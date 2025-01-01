# typed: true
# frozen_string_literal: true

class Stafftools::ModelsController < StafftoolsController
  include GitHubModels::PlaygroundDependency
  include GitHubModels::BillingDependency

  NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS = 60

  before_action :dotcom_required
  before_action :require_user, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Configurations,
    only: [:show]

  CSP_EXCEPTIONS = {
    img_src: [SecureHeaders::PolicyManagement::DATA_PROTOCOL],
  }.freeze
  before_action :add_csp_exceptions, only: [:index]

  PER_PAGE = 30
  GROUP_OPTIONS = %w[publisher visibility]

  def index
    group_by = GROUP_OPTIONS.include?(params[:group_by]) ? params[:group_by] : "publisher"
    models = GitHubModels.domain.models.find_many
    models.sort_by! do |model|
      [
        (group_by == "visibility" ? model.visibility : model.publisher)&.downcase,
        T.must(model.friendly_name).downcase
      ]
    end
    models = models.paginate(page: current_page, per_page: PER_PAGE)

    groups = models.map { |model| group_by == "publisher" ? model.publisher : model.visibility }.uniq

    render "stafftools/models/index", locals: {
      models: models,
      visibilities: GitHubModels.domain.models.visibilities,
      group_by: group_by,
      group_options: GROUP_OPTIONS,
      groups: groups,
    }
  end

  def show
    if this_user.organization?
      policy = GitHubModels::OrganizationAccessPolicy.new(org: this_user)
      model_access_rules = load_model_access_rules
      render "stafftools/models/org_show", locals: {
        org: this_user,
        models_enabled: policy.models_enabled_for_org?,
        allowed_models: model_access_rules.any? ? policy.allowed_custom_models + policy.allowed_default_models : [],
        model_access_rules_enabled: model_access_rules.any?,
        org_access_rules_publisher: model_access_rules.select(&:publisher_specific?),
        org_access_rules_custom_key: model_access_rules.select(&:custom_key_specific?),
        org_access_rules_model: model_access_rules.select(&:default_model_specific?),
        org_access_rules_custom_model: model_access_rules.select(&:custom_model_specific?),
        is_allowlist: policy.allowlist?,
        billing_enabled: this_user.models_billing_enabled?,
        models_billing_disabled_by_non_payment_method_reason: this_user.models_billing_disabled_by_non_payment_method_reason?,
        can_show_models_billing: this_user.can_show_models_billing?,
        can_enable_models_billing: this_user.can_enable_models_billing?,
        has_payment_method: this_user.has_payment_method?,
        enabled_models_billing: this_user.models_billing_enabled?,
      }, layout: "layouts/stafftools/organization/content"
    else
      is_high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(this_user)
      duplicate_emails = GitHub::SpamChecker.find_obfuscated_duplicate_emails(this_user)
      GitHub::PrefillAssociations.prefill_associations(duplicate_emails, :user)
      account_type = this_user.type.downcase
      render "stafftools/models/show", locals: {
        user: this_user,
        account_type: account_type,
        is_new_account: this_user.created_at && this_user.created_at >= NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS.days.ago,
        is_high_profile: is_high_profile,
        high_profile_reason: high_profile_reason,
        duplicate_emails: duplicate_emails,
        blocks: GitHubModels.domain.blocks.history_for(user: this_user),
        blocked: GitHubModels.domain.blocks.exists?(this_user),
        access_result: GitHubModels::PlaygroundAccessResult.for(this_user),
        auths_count: GitHubModels.domain.usage.auths_count_for_user_id(this_user.id),
        can_show_models_billing: this_user.can_show_models_billing?,
        can_enable_models_billing: this_user.can_enable_models_billing?,
        has_payment_method: this_user.has_payment_method?,
        enabled_models_billing: this_user.models_billing_enabled?,
        billing_enabled: this_user.models_billing_enabled?,
        models_billing_disabled_by_non_payment_method_reason: this_user.models_billing_disabled_by_non_payment_method_reason?,
      }, layout: "layouts/stafftools/user/content"
    end
  end

  def update
    GitHubModels::FetchCatalogItemsJob.perform_later
    flash[:notice] = "The job has been enqueued to update the catalog data."

    redirect_to :back
  end

  def update_visibility # rubocop:todo GitHub/UseRestfulActions
    model = GitHubModels.domain.models.find!(id: params[:id])
    GitHubModels.domain.models.update_visibility(model, params[:visibility])
    flash[:notice] = "Visibility for \"#{model.name}\" set to \"#{params[:visibility]}\""

    redirect_to :back
  end

  private

  sig { returns T::Array[GitHubModels::OrganizationAccessRule] }
  def load_model_access_rules
    result = this_user.github_models_access_rules.targeted.order(:id).to_a
    GitHub::PrefillAssociations.prefill_associations(result, %i(publisher model custom_model custom_key))
    result
  end

  def require_user
    render_404 unless this_user
  end
end
