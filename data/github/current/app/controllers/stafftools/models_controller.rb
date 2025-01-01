# typed: true
# frozen_string_literal: true

class Stafftools::ModelsController < StafftoolsController
  include GitHubModels::PlaygroundDependency

  NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS = 60

  before_action :dotcom_required

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

    catalog_sync_job_enabled = GitHub.flipper[:project_neutron_fetch_catalog_items_job].enabled?
    render "stafftools/models/index", locals: {
      models: models,
      catalog_sync_job_enabled: catalog_sync_job_enabled,
      visibilities: GitHubModels.domain.models.visibilities,
      group_by: group_by,
      group_options: GROUP_OPTIONS,
      groups: groups,
    }
  end

  def show
    if this_user.organization?
      policy = GitHubModels::OrganizationAccessPolicy.new(org: this_user)
      model_access_rules = this_user.github_models_access_rules.targeted
      GitHub::PrefillAssociations.prefill_associations(model_access_rules, %i(publisher model))
      render "stafftools/models/org_show", locals: {
        org: this_user,
        models_enabled: policy.models_enabled_for_org?,
        model_access_rules_enabled: model_access_rules.any?,
        org_access_rules_publisher: model_access_rules.select(&:publisher_specific?),
        org_access_rules_model: model_access_rules.select(&:default_model_specific?),
        is_allowlist: policy.allowlist?,
        org_access_policies_ff_enabled: this_user.feature_enabled?(:github_models_org_access_policies),
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
        auths_count: GitHubModels.domain.usage.auths_count_for_user_id(this_user.id)
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
end
