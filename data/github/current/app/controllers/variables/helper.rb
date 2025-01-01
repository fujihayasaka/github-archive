# typed: true
# frozen_string_literal: true

require "github/kredz_client"

module Variables::Helper
  include GitHub::KredzClient
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  sig { returns(Integer) }
  def variables_per_page
    @variables_per_page || 1000
  end

  sig { params(value: Integer).returns(T.nilable(Integer)) }
  def variables_per_page=(value)
    @variables_per_page = T.let(value, T.nilable(Integer))
  end

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :ensure_variable_enabled
  end

  private

  sig { params(owner: T.any(Environment, Repository, Organization), app: T.untyped).returns(T.untyped) }
  def variables_for(owner, app:)
    Variables.for_app(app, owner: owner, actor: current_user)
  rescue Variables::Error
    flash[:error] = "Failed to load variables. Please refresh and try again."
    []
  end

  sig do
    params(owner: T.any(Repository, Organization), app: T.untyped, page: Integer)
    .returns(T::Hash[Symbol, T.untyped])
  end
  def paginated_variables_for(owner, app:, page:)
    Variables.for_app_paginated(app, owner: owner, actor: current_user, page: page, per_page: variables_per_page)
  rescue Variables::Error
    flash[:error] = "Failed to load variables. Please refresh and try again."
    {
      variables: [],
      total_count: 0,
    }
  end

  sig do
    params(repository: Repository, actor: User, app: T.untyped, fetch_environments: T::Boolean)
    .returns(T::Hash[Symbol, T::Array[T.untyped]])
  end
  def variables_for_repository(repository, actor, app:, fetch_environments: false)
    Variables.for_repository(repository, actor: actor, app: app, fetch_environments: fetch_environments)
  rescue Variables::Error
    flash[:error] = "Failed to load variables. Please refresh and try again."
    {
      repository_variables: [],
      organization_variables: [],
      environment_variables: [],
    }
  end

  sig do
    params(repository: Repository, actor: T.nilable(User), app: T.untyped)
    .returns(T::Hash[Symbol, T::Array[T.untyped]])
  end
  def variable_names_for_repository(repository, actor, app:)
    Variables.list_variable_names_for_repository(repository, actor: actor, app: app)
  rescue Variables::Error
    flash[:error] = "Failed to load variable names. Please refresh and try again."
    {
      repository_variable_names: [],
      organization_variable_names: [],
    }
  end

  sig do
    params(repository: Repository, actor: T.nilable(User), app: T.untyped, page: Integer)
    .returns(T::Hash[Symbol, T.untyped])
  end
  def env_variables_for_repository(repository, actor, app:, page:)
    Variables.for_repository_environments(repository, actor: actor, app: app, page: page, per_page: variables_per_page)
  rescue Variables::Error
    flash[:error] = "Failed to load environment variables. Please refresh and try again."
    {
      environment_variables: [],
      total_count: 0,
    }
  end

  sig do
    params(repository: Repository, actor: T.nilable(User), app: T.untyped, page: Integer)
    .returns(T::Hash[Symbol,  T.untyped])
  end
  def org_variables_for_repository(repository, actor, app:, page:)
    Variables.for_repository_organizations(repository, actor: actor, app: app, page: page, per_page: variables_per_page)
  rescue Variables::Error
    flash[:error] = "Failed to load organization variables. Please refresh and try again."
    {
      organization_variables: [],
      total_count: 0,
    }
  end

  sig { void }
  def ensure_variable_enabled
    render_404 unless variables_enabled?
  end

  sig { returns(T::Boolean) }
  def variables_enabled?
    return @_app_enabled if defined?(@_app_enabled)

    @_app_enabled ||= Variables::AppsHelper.variables_enabled_for?(app_name, current_user)
  end

  sig { returns(String) }
  def app_name
    params[:app_name] || Variables::AppsHelper::ACTIONS_APP_NAME
  end

  sig { returns(T::Boolean) }
  def show_environment_variables?
    app_name == Variables::AppsHelper::ACTIONS_APP_NAME && current_repository.can_use_environments?
  end

  sig { params(org: T.any(Organization, User)).returns(T::Boolean) }
  def can_use_org_variables(org)
    case
    when org.class == Organization
      T.cast(org, Organization).can_use_org_variables?
    when org.class == User
      # Users can't use organization variables.
      false
    else
      # return false in any other scenario
      false
    end
  end

  sig do
    params(
      variable: GitHub::Kredz::Services::Varz::Variable,
      can_use_variables_for_private_repos: T::Boolean,
      is_enterprise: T::Boolean
    ).returns(String)
  end
  def visibility_description_for_variable(variable, can_use_variables_for_private_repos, is_enterprise)
    case variable.visibility
    when GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_ALL_REPOS
      can_use_variables_for_private_repos && "all repositories" || "public repositories"
    when GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_PRIVATE_REPOS
      is_enterprise && "private and internal repositories" || "private repositories"
    when GitHub::KredzClient::Varz::VARIABLE_VISIBILITY_SELECTED_REPOS
      "#{variable.selected_repositories_count} #{"repository".pluralize(variable.selected_repositories_count)}"
    else
      ""
    end
  end

  sig { params(variable_name: T.nilable(String)).returns(String) }
  def repository_items_aria_id_prefix(variable_name: nil)
    return app_name unless variable_name.present?
    "#{app_name}-#{variable_name}"
  end

  sig { returns(String) }
  def blank_slate_title
    if app_name == Variables::AppsHelper::ACTIONS_APP_NAME
      "No workflows have been added to this repository."
    else
      "You do not have access to #{Secrets::AppsHelper.display_name_for(app_name)} variables."
    end
  end

  sig { returns(String) }
  def blank_slate_description
    "Variables allow you to store non-sensitive information, such as username, in your repository."
  end

  sig do
    params(repository: Repository, app: T.untyped, environments: T.untyped)
    .returns(T.untyped)
  end
  def variable_count_for_environments(repository, app:, environments:)
    Variables.variable_count_for_environments(repository, app: app, environments: environments)
  rescue Variables::Error
    flash[:error] = "Failed to load variables. Please refresh and try again."
    []
  end

  sig { returns(T::Boolean) }
  def repo_can_use_org_variables?
    return false unless can_use_org_variables(current_repository.owner)
    return true if current_repository.public?

    plan_name = current_repository.async_actions_plan_owner.sync.plan_name
    plan_name != ActionsPlanOwner::FREE && plan_name != ActionsPlanOwner::FREE_ORGANIZATION
  end
end
