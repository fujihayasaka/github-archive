# typed: true
# frozen_string_literal: true

class Users::Settings::SecurityProductsController < ApplicationController
  include ReactHelper
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency
  include Settings::SecurityProducts::RepositoriesHelper
  include ApplicationController::JsonDependency
  include SharedSecurityConfigurationsDependency

  sig { returns(String) }
  def self.react_bundle_name
    "security-products-enablement"
  end

  allow_verified_fetch only: [:create, :update, :destroy, :repositories_count]

  # Access
  # before_action :login_required
  before_action :ensure_security_configurations_enabled, only: [
    :create,
    :edit,
    :new,
    :show,
  ]

  before_action :parse_json_params, only: [:create, :update]
  before_action :security_configuration, only: [:edit, :show, :update, :repositories_count]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    only: [:index, :new, :edit, :show, :repositories_count]

  sig { void }
  def index
    repos = serialized_repos
    render_react_app(
      payload: default_payload.merge({
        githubRecommendedConfiguration: serialized_github_recommended_configuration,
        customSecurityConfigurations: serialized_security_configurations,
        repositories: repos[:repositories],
        totalRepositoryCount: repos[:total_repository_count],
        pageCount: repos[:page_count],
        showInfoBanner: false,
        showTalkToUsBanner: false,
      }),
      title: "Settings · Code security · #{current_user&.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "user_settings",
      ssr: true,
    )
  end

  def new
    render_react_app(
      payload: default_payload,
      title: "Settings · New security configuration · #{current_user&.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "user_settings",
      ssr: true,
    )
  end

  def edit
    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Settings · Edit security configuration · #{current_user&.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "user_settings",
      ssr: true,
    )
  end

  sig { void }
  def create
    saved_config = SecurityConfiguration.create_configuration(
      security_configuration_params(T.must(current_user)).merge({ "target" => current_user }),
      params[:default_for_new_public_repos],
      params[:default_for_new_private_repos],
      params[:enforcement]&.to_sym,
      current_user,
      params[:options],
    )

    if saved_config.errors.any?
      render json: { errors: serialize_errors(saved_config.errors) }, status: :unprocessable_entity
    else
      render json: {}, status: :created
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Settings · Show security configuration · #{current_user&.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "user_settings",
      ssr: true,
    )
  end

  sig { void }
  def update
    security_configuration.update_configuration(
      security_configuration_params(T.must(current_user)).merge({ "target" => current_user }),
      T.must(current_user),
      type: :user,
      default_for_new_public_repos: params[:default_for_new_public_repos],
      default_for_new_private_repos: params[:default_for_new_private_repos],
      enforcement: params[:enforcement]&.to_sym,
      options: params[:options],
    )

    if security_configuration.errors.any?
      render json: { errors: serialize_errors(security_configuration.errors) }, status: :unprocessable_entity
    else
      render json: {}, status: :ok
    end

  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  sig { void }
  def destroy
    security_configuration = SecurityConfiguration.find_by(target: [current_user], id: params[:id])
    if security_configuration.present?
      security_configuration.delete_configuration(current_user)
      head :no_content
    else
      render_404
    end
  end

  def repositories_count # rubocop:todo GitHub/UseRestfulActions
    render json: {
      repo_count: security_configuration_serializer.repositories_count(security_configuration)
    }
  end

  private

  def ensure_security_configurations_enabled
    render_404 unless current_user&.feature_enabled?(:user_security_configurations)
  end

  sig { returns(SecurityConfiguration) }
  memoize def security_configuration
    find_security_configuration([current_user])
  end

  def default_payload
    payload = shared_default_payload
    payload.merge({
      renderContext: "user",
      user: current_user&.display_login,
    })
  end

  sig { returns(SecurityProductsEnablement::SecurityConfigurationSerializer) }
  memoize def security_configuration_serializer
    SecurityProductsEnablement::SecurityConfigurationSerializer.new(T.must(current_user))
  end

  def serialized_github_recommended_configuration
    security_configuration_serializer.serialize(github_recommended_configuration) if github_recommended_configuration
  end

  memoize def security_configurations
    SecurityConfiguration.where(target_type: "User", target: current_user).order(:id)
  end

  def serialized_security_configurations
    security_configuration_serializer.serialize_collection(security_configurations.to_a)
  end

  def serialized_repos(repository_ids: nil)
    search_query = params[:q] || ""
    serialized_repositories(organization: nil, user: T.must(current_user), user_session:, cap_filter:, repository_ids: repository_ids, search_query:, current_page:)
  end
end
