# typed: true
# frozen_string_literal: true

class Stafftools::ModelsController < StafftoolsController
  include Marketplace::Models::PlaygroundDependency

  NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS = 60

  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  CSP_EXCEPTIONS = {
    img_src: [SecureHeaders::PolicyManagement::DATA_PROTOCOL],
  }.freeze
  before_action :add_csp_exceptions, only: [:index]

  PER_PAGE = 30
  GROUP_OPTIONS = %w[publisher visibility]

  def index
    group_by = GROUP_OPTIONS.include?(params[:group_by]) ? params[:group_by] : "publisher"
    catalog_items = GitHubModels::CatalogItem.all.order(:id).sort_by do |item|
      [
        (group_by == "visibility" ? item.visibility : item.publisher).downcase,
        T.must(item.friendly_name).downcase
      ]
    end.paginate(per_page: PER_PAGE, page: current_page)

    groups = catalog_items.map { |item| group_by == "publisher" ? item.publisher : item.visibility }.uniq

    catalog_sync_job_enabled = GitHub.flipper[:project_neutron_fetch_catalog_items_job].enabled?
    render "stafftools/models/index", locals: {
      catalog_items: catalog_items,
      catalog_sync_job_enabled: catalog_sync_job_enabled,
      visibilities: GitHubModels::CatalogItem.visibilities.keys,
      group_by: group_by,
      group_options: GROUP_OPTIONS,
      groups: groups,
    }
  end

  def show
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
      blocks: GitHubModels::Block.where(user: this_user).order(created_at: :desc),
      blocked: GitHubModels::Block.blocked?(this_user),
      access_result: GitHubModels::PlaygroundAccessResult.for(this_user),
      auths_count: GitHubModels::UsageDetails.auths_count_for_user_id(this_user.id)
    }, layout: "layouts/stafftools/user/content"
  end

  def update
    GitHubModels::FetchCatalogItemsJob.perform_later
    flash[:notice] = "The job has been enqueued to update the catalog data."

    redirect_to :back
  end

  def update_visibility # rubocop:todo GitHub/UseRestfulActions
    catalog_item = GitHubModels::CatalogItem.find(params[:id])
    catalog_item.update!(visibility: params[:visibility])
    flash[:notice] = "Visibility for \"#{catalog_item.name}\" set to \"#{params[:visibility]}\""

    redirect_to :back
  end
end
