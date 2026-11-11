# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::CodeReviewApprovalRepositoryItemsController < Orgs::CopilotSettings::BaseController
  APPROVAL_FORM_ID = T.let("copilot-code-review-approval-access-form", String)
  QUALIFIED_APPROVAL_FORM_ID = T.let("copilot-code-review-qualified-approval-access-form", String)

  APPROVAL_ARIA_ID_PREFIX = T.let("copilot-code-review-approval-access", String)
  QUALIFIED_APPROVAL_ARIA_ID_PREFIX = T.let("copilot-code-review-qualified-approval-access", String)

  before_action :check_not_legacy_plan
  before_action :check_copilot_available
  before_action :ensure_code_review_settings_enabled
  before_action :ensure_page_specified
  before_action :ensure_setting_type

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  sig { void }
  def index
    selected_repo_ids = selected_repository_ids

    render(Organizations::Settings::RepositoryItemsComponent.new(
      organization: current_organization,
      repositories: additional_repositories(selected_repo_ids),
      selected_repositories: selected_repo_ids,
      current_page: page,
      total_count: available_repository_count(selected_repo_ids),
      data_url: settings_org_copilot_code_review_approval_repository_items_path(
        current_organization,
        page: page + 1,
        setting_type: setting_type,
      ),
      aria_id_prefix: aria_id_prefix,
      repository_identifier_key: :id,
      form_id: form_id,
    ), layout: false)
  end

  private

  sig { void }
  def ensure_page_specified
    render_404 unless page > 0
  end

  sig { returns(Integer) }
  def page
    params[:page].to_i
  end

  sig { params(selected_repository_ids: T::Set[Integer]).returns(T.untyped) }
  def additional_repositories(selected_repository_ids)
    Repositories.domain.by_org_excluding(
      organization_id: current_organization.id,
      excluded_repo_ids: selected_repository_ids,
      pagination: GH::Pagination::Offset.new(page: page, per_page: Orgs::RepositoryItemsHelper::PER_PAGE),
      max_pages: Orgs::RepositoryItemsHelper::MAX_PAGES * Orgs::RepositoryItemsHelper::PER_PAGE,
      public_only: false,
    )
  end

  sig { void }
  def ensure_code_review_settings_enabled
    render_404 unless code_review_approval_settings_enabled?
  end

  sig { void }
  def ensure_setting_type
    render_404 unless code_review_approval_setting_type_enabled_for_current_rollout?(setting_type)
  end

  sig { returns(T.nilable(Symbol)) }
  def setting_type
    case params[:setting_type].presence || params[:settingType].to_s
    when "approval"
      :approval
    when "qualified_approval"
      :qualified_approval
    else
      nil
    end
  end

  sig { returns(T::Set[Integer]) }
  def selected_repository_ids
    selected_repository_id_scope
      .pluck(:repository_id)
      .to_set
  end

  sig { returns(T.untyped) }
  def selected_repository_id_scope
    PullRequests::Copilot::RepoEnablement
      .for_repos_owned_by(current_organization)
      .where(setting_type: PullRequests::Copilot::RepoEnablement.setting_type_value(T.must(setting_type)))
      .select(:repository_id)
  end

  sig { params(selected_repository_ids: T::Set[Integer]).returns(Integer) }
  def available_repository_count(selected_repository_ids)
    selected_active_repository_count = active_selected_repository_count(selected_repository_ids)
    max_repository_count = Orgs::RepositoryItemsHelper::MAX_PAGES * Orgs::RepositoryItemsHelper::PER_PAGE

    [
      ::Repositories::Public.active_owned_by(current_organization.id)
        .limit(max_repository_count + selected_active_repository_count)
        .count - selected_active_repository_count,
      0,
    ].max
  end

  sig { params(selected_repository_ids: T::Set[Integer]).returns(Integer) }
  def active_selected_repository_count(selected_repository_ids)
    return 0 if selected_repository_ids.empty?

    ::Repositories::Public.active_owned_by(current_organization.id)
      .where(id: selected_repository_ids.to_a)
      .limit(selected_repository_ids.size)
      .count
  end

  sig { returns(String) }
  def form_id
    case setting_type
    when :approval
      APPROVAL_FORM_ID
    when :qualified_approval
      QUALIFIED_APPROVAL_FORM_ID
    else
      raise "unreachable"
    end
  end

  sig { returns(String) }
  def aria_id_prefix
    case setting_type
    when :approval
      APPROVAL_ARIA_ID_PREFIX
    when :qualified_approval
      QUALIFIED_APPROVAL_ARIA_ID_PREFIX
    else
      raise "unreachable"
    end
  end
end
