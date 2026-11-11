# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::CodeReviewApprovalsController < Orgs::CopilotSettings::BaseController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  INVALID_ACCESS_PARAM = T.let("__invalid__", String)
  SELECTED_REPOSITORY_HYDRATION_LIMIT = T.let(Orgs::RepositoryItemsHelper::PER_PAGE, Integer)

  allow_verified_fetch only: [:update]

  before_action :check_not_legacy_plan
  before_action :check_copilot_available
  before_action :ensure_code_review_settings_enabled
  before_action :parse_json_params, only: [:update]

  stylesheet_bundle :suggestions, :copilot
  javascript_bundle :settings
  javascript_bundle ::Copilot::CodeReviewSettings::REACT_BUNDLE_NAME, only: [:index]

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
    render "settings/organization/copilot/code_review_approvals/index", locals: {
      code_review_settings_props: code_review_settings_props,
    }
  end

  sig { void }
  def update
    access = resolved_access
    submitted_access = access_param

    return head :bad_request unless code_review_approval_setting_type_enabled_for_current_rollout?(setting_type)

    case setting_type
    when :approval
      return head :bad_request unless Configurable::CopilotCodeReviewApprovalAccess::State.try_deserialize(access)

      current_organization.update_copilot_code_review_approval_access(access, false, actor: current_user) if submitted_access.present?
    when :qualified_approval
      return head :bad_request unless Configurable::CopilotCodeReviewQualifiedApprovalAccess::State.try_deserialize(access)

      current_organization.update_copilot_code_review_qualified_approval_access(access, false, actor: current_user) if submitted_access.present?
    else
      return head :bad_request
    end

    update_selected_repositories(access) if submitted_access.present? || repository_selection_submitted?

    if async_update_request?
      head :ok
    else
      flash[:notice] = success_message
      redirect_to code_review_path
    end
  rescue ArgumentError => error
    if async_update_request?
      render json: { error: error.message }, status: :unprocessable_entity
    else
      flash[:error] = error.message
      redirect_to code_review_path
    end
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def code_review_settings_props
    {
      orgLogin: current_organization.display_login,
      settings: settings_props,
    }
  end

  sig { void }
  def ensure_code_review_settings_enabled
    render_404 unless code_review_approval_settings_enabled?
  end

  sig { returns(T::Boolean) }
  def async_update_request?
    request.xhr? || request.format.json?
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def settings_props
    props = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
    props << approval_setting_props if code_review_approval_setting_enabled_for_current_rollout?
    props << qualified_approval_setting_props if code_review_qualified_approval_setting_enabled_for_current_rollout?
    props
  end

  sig { returns(T::Array[Integer]) }
  def normalized_repository_ids
    Array(repository_ids_param)
      .filter_map { |value| normalized_repository_id(value) }
      .uniq
  end

  sig { params(access: String).void }
  def update_selected_repositories(access)
    return if access == "multiple" && !repository_selection_submitted?

    repository_ids = access == "multiple" ? normalized_repository_ids : []

    PullRequests::Copilot::RepoEnablement.enable_for_repositories!(
      repository_ids: repository_ids,
      owner: current_organization,
      actor: current_user,
      setting_type: T.must(setting_type),
    )
  end

  sig { params(value: T.untyped).returns(T.nilable(Integer)) }
  def normalized_repository_id(value)
    raw_value = value.to_s
    return if raw_value.blank?

    if raw_value.match?(/\A\d+\z/)
      id = raw_value.to_i
      return id if id.positive?
    end

    type, global_id = Platform::Helpers::NodeIdentification.from_global_id(raw_value)
    return unless type == "Repository"

    id = global_id.to_i
    id if id.positive?
  rescue StandardError
    nil
  end

  sig { returns(T::Boolean) }
  def repository_selection_submitted?
    params.key?(:selected_repos) ||
      params.key?(:selectedRepos) ||
      params.key?(:repository_ids) ||
      truthy_param?(params[:repository_selection_submitted]) ||
      truthy_param?(params[:repositorySelectionSubmitted])
  end

  sig { params(value: T.untyped).returns(T::Boolean) }
  def truthy_param?(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
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

  sig { returns(String) }
  def success_message
    case setting_type
    when :approval
      "Copilot approval repository policy updated."
    when :qualified_approval
      "Copilot approval merge requirements policy updated."
    else
      "Copilot code review approval settings updated."
    end
  end

  sig { returns(String) }
  def code_review_path
    settings_org_copilot_code_review_path(current_organization)
  end

  sig { returns(String) }
  def resolved_access
    access_param.presence || current_access&.serialize.to_s
  end

  sig { returns(String) }
  def access_param
    raw_access = if params.key?(:mode)
      params[:mode]
    elsif params.key?(:access)
      params[:access]
    elsif params.key?(:visibility)
      params[:visibility]
    else
      return ""
    end

    return INVALID_ACCESS_PARAM unless raw_access.is_a?(String)
    return "" if raw_access.blank?

    normalize_access_param(raw_access)
  end

  sig { params(raw_access: String).returns(String) }
  def normalize_access_param(raw_access)
    case raw_access
    when "selected_repos"
      "multiple"
    else
      raw_access
    end
  end

  sig { returns(T.untyped) }
  def repository_ids_param
    return params[:selected_repos] if params.key?(:selected_repos)
    return params[:selectedRepos] if params.key?(:selectedRepos)

    params[:repository_ids]
  end

  sig { returns(T.nilable(T.any(Configurable::CopilotCodeReviewApprovalAccess::State, Configurable::CopilotCodeReviewQualifiedApprovalAccess::State))) }
  def current_access
    case setting_type
    when :approval
      current_organization.copilot_code_review_approval_access
    when :qualified_approval
      current_organization.copilot_code_review_qualified_approval_access
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def approval_setting_props
    build_setting_props(
      setting_type: :approval,
      title: "Allow Copilot to approve pull requests",
      description: "Choose where Copilot can approve pull requests in this organization.",
      mode: current_organization.copilot_code_review_approval_access.serialize,
      selection: selected_repository_props_for(:approval),
      repository_selection_description: "Select the repositories where Copilot can approve pull requests.",
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def qualified_approval_setting_props
    build_setting_props(
      setting_type: :qualified_approval,
      title: "Count Copilot approvals toward merge requirements",
      description: "Choose where Copilot approvals can count toward merge requirements in this organization.",
      mode: current_organization.copilot_code_review_qualified_approval_access.serialize,
      selection: selected_repository_props_for(:qualified_approval),
      repository_selection_description: "Select the repositories where Copilot approvals can count toward merge requirements.",
    )
  end

  sig do
    params(
      setting_type: Symbol,
      title: String,
      description: String,
      mode: String,
      selection: T::Array[T::Hash[Symbol, T.untyped]],
      repository_selection_description: String,
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def build_setting_props(setting_type:, title:, description:, mode:, selection:, repository_selection_description:)
    {
      settingType: setting_type.to_s,
      title: title,
      description: description,
      mode: mode,
      selection: selection,
      callbackPath: settings_org_copilot_code_review_update_path(current_organization),
      modeOptions: access_options_for(setting_type),
      repositorySelectionTitle: "Selected repositories",
      repositorySelectionDescription: repository_selection_description,
    }
  end

  sig { params(setting_type: Symbol).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def selected_repository_props_for(setting_type)
    selected_repository_ids = active_selected_repository_ids_for(selected_repository_ids_for(setting_type))
    return [] if selected_repository_ids.empty?

    hydrated_repository_ids = selected_repository_ids.first(SELECTED_REPOSITORY_HYDRATION_LIMIT)
    hydrated_repositories_by_id = T.let(
      ::Repositories::Public.active_owned_by(current_organization.id)
        .where(id: hydrated_repository_ids)
        .index_by(&:id),
      T::Hash[Integer, ::Repository],
    )

    selected_repository_ids.map do |repository_id|
      repository = hydrated_repositories_by_id[repository_id]
      repository ? format_selected_repo(repository) : format_selected_repo_id(repository_id)
    end
  end

  sig { params(setting_type: Symbol).returns(T::Array[Integer]) }
  def selected_repository_ids_for(setting_type)
    PullRequests::Copilot::RepoEnablement
      .for_repos_owned_by(current_organization)
      .where(setting_type: PullRequests::Copilot::RepoEnablement.setting_type_value(setting_type))
      .pluck(:repository_id)
  end

  sig { params(repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def active_selected_repository_ids_for(repository_ids)
    return [] if repository_ids.empty?

    ::Repositories::Public.active_owned_by(current_organization.id)
      .where(id: repository_ids)
      .pluck(:id)
  end

  sig { params(repository: ::Repository).returns(T::Hash[Symbol, T.untyped]) }
  def format_selected_repo(repository)
    {
      id: repository.id,
      nodeId: repository.global_relay_id,
      name: repository.name,
      ownerLogin: current_organization.display_login,
      visibility: repository.visibility,
    }
  end

  sig { params(repository_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
  def format_selected_repo_id(repository_id)
    {
      id: repository_id,
      nodeId: Platform::Helpers::NodeIdentification.to_global_id("Repository", repository_id),
    }
  end

  sig { params(setting_type: Symbol).returns(T::Array[T::Hash[Symbol, String]]) }
  def access_options_for(setting_type)
    enabled_everywhere_description = if setting_type == :approval
      "Copilot approvals are enabled for every repository in this organization."
    else
      "Copilot approvals can count toward merge requirements in every repository in this organization."
    end

    selected_repositories_description = if setting_type == :approval
      "Copilot approvals are enabled only in the repositories you select."
    else
      "Copilot approvals can count toward merge requirements only in the repositories you select."
    end

    disabled_everywhere_description = if setting_type == :approval
      "Copilot approvals are disabled for every repository in this organization."
    else
      "Copilot approvals cannot count toward merge requirements in any repository in this organization."
    end

    [
      {
        name: "all_repos",
        label: "Enabled everywhere",
        description: enabled_everywhere_description,
      },
      {
        name: "no_policy",
        label: "Let repositories decide",
        description: "Repository admins can decide this in repository settings.",
      },
      {
        name: "multiple",
        label: "Enable for selected repositories",
        description: selected_repositories_description,
      },
      {
        name: "no_repos",
        label: "Disabled everywhere",
        description: disabled_everywhere_description,
      },
    ]
  end
end
