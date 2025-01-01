# typed: strict
# frozen_string_literal: true

class RepositoryCustomPropertiesController < AbstractRepositoryController
  include Orgs::CustomPropertiesHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update]
  before_action :ensure_owner_is_org
  before_action :check_access, only: [:settings, :update]
  before_action :sudo_filter, only: [:update]
  before_action :try_parse_json_params, only: [:update]

  sig { returns(String) }
  def self.react_bundle_name
    "custom-properties"
  end

  javascript_bundle :settings
  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
  only: [:settings, :overview]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    optional: true,
    only: [:settings, :overview]

  sig { returns(T.untyped) }
  def settings # rubocop:todo GitHub/UseRestfulActions
    values = T.must(Repositories.domain.custom_properties.repo_properties([current_repository], :effective)[current_repository])
    definitions = definitions_manager.get_definitions

    repo_payload = nil
    editable_properties = []
    repo_payload = repos_properties_payload([current_repository]).first

    permissions = CustomProperties::Public.user_edit_permissions(current_user, current_repository)
    if permissions.org
      editable_properties = definitions.map { |d| d.property_name }
    elsif permissions.repo
      editable_properties = definitions.filter_map { |d| d.property_name if d.values_editable_by == "org_and_repo_actors" }
    end

    add_client_feature_flag([:custom_properties_editing_redesign])

    render_react_app(
      payload: {
        definitions: definitions_payload(definitions),
        properties: values,
        currentRepo: repo_payload,
        editableProperties: editable_properties,
        errors: {},
      },
      title: "Settings · Custom properties · #{current_repository.name_with_display_owner}",
      page_data: {
        selected_link: :repo_custom_properties,
      },
      layout: "layouts/repository_settings"
    )
  end

  sig { returns(T.untyped) }
  def overview # rubocop:todo GitHub/UseRestfulActions
    values = T.must(Repositories.domain.custom_properties.repo_properties([current_repository], :effective, strip_nils: true)[current_repository])
    definitions = definitions_manager.get_definitions

    user = current_user
    can_edit_properties = if user
      CustomProperties::Public.user_edit_permissions(user, current_repository).repo
    else
      false
    end

    render_react_app(
      payload: {
        definitions: definitions_payload(definitions),
        values: values,
        canEditProperties: can_edit_properties,
      },
      title: "Settings · Custom properties · #{current_repository.name_with_display_owner}",
    )
  end

  sig { returns(T.untyped) }
  def update
    return head :bad_request unless params[:properties]

    payload = params.slice(:properties).permit!

    begin
      values_manager.set_properties_for([current_repository], payload[:properties].to_h, actor: current_user)
      head :ok
    rescue CustomProperties::Errors::EditPropertyPermissionError => error
      render json: { error: error.full_message }, status: 403
    rescue CustomProperties::Errors::PropertyValidationError => error
      render json: { error: error.message }, status: 422
    end
  end

  private

  sig { returns(T.untyped) }
  def ensure_owner_is_org
    render_404 unless current_repository.owner.organization?
  end

  sig { returns(CustomPropertiesDefinitionsManager) }
  memoize def definitions_manager
    CustomProperties::Public.definitions_manager(current_repository.owner)
  end

  sig { returns(CustomPropertiesValuesManager) }
  memoize def values_manager
    CustomProperties::Public.values_manager(definitions_manager)
  end

  sig { void }
  def ensure_repo_fgp
    render_404 unless logged_in? && current_repository.async_can_edit_custom_property_values_as_repo_actor?(current_user).sync
  end

  sig { void }
  def check_access
    ensure_repo_fgp
  end
end
