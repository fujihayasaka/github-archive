# typed: strict
# frozen_string_literal: true

class RepositoryCustomPropertiesController < AbstractRepositoryController
  include Orgs::CustomPropertiesHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:update, :suggest_value]
  before_action :ensure_owner_is_org
  before_action :check_access, only: [:settings, :update, :suggest_value]
  before_action :sudo_filter, only: [:update]
  before_action :try_parse_json_params, only: [:update, :suggest_value]

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
    definitions = Repositories.domain.custom_properties.get_definitions(current_repository.owner)

    repo_payload = nil
    editable_properties = []
    repo_payload = repos_properties_payload([current_repository]).first

    permissions = Repositories.domain.custom_properties.user_edit_permissions(current_user, current_repository)

    if permissions.org
      editable_properties = definitions.map { |d| d.property_name }
    elsif permissions.repo
      editable_properties = definitions.filter_map { |d| d.property_name if d.values_editable_by == "org_and_repo_actors" }
    end

    render_react_app(
      payload: {
        definitions: definitions_payload(definitions),
        properties: values,
        currentRepo: repo_payload,
        editableProperties: editable_properties,
        propertiesLimits: properties_limits_payload(Repositories.domain.custom_properties.limits(current_repository.owner)),
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
    definitions = Repositories.domain.custom_properties.get_definitions(current_repository.owner)

    user = current_user
    can_edit_properties = if user
      Repositories.domain.custom_properties.user_edit_permissions(user, current_repository).repo
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

    payload = params.slice(:properties, :metrics).permit!
    properties = T.cast(payload[:properties].to_h, T::Hash[String, String])

    metrics = payload[:metrics]&.to_h

    if metrics
      copilot_suggestions_attempted = metrics[:copilotSuggestionsAttempted].to_i
      copilot_suggestions_accepted = metrics[:copilotSuggestionsAccepted].to_i

      GitHub.dogstats.distribution("custom_properties_settings.update_repos_properties.copilot_suggestions_attempted", copilot_suggestions_attempted)
      GitHub.dogstats.distribution("custom_properties_settings.update_repos_properties.copilot_suggestions_accepted", copilot_suggestions_accepted)

      if copilot_suggestions_attempted > 0
        acceptance_ratio = copilot_suggestions_accepted.to_f / copilot_suggestions_attempted
        GitHub.dogstats.histogram("custom_properties_settings.update_repos_properties.copilot_suggestions_acceptance_ratio", acceptance_ratio)
      end

      if properties.size > 0
        attempts_to_properties_ratio = copilot_suggestions_attempted.to_f / properties.size
        GitHub.dogstats.histogram("custom_properties_settings.update_repos_properties.copilot_suggestions_attempts_per_property", attempts_to_properties_ratio)
      end
    end

    begin
      Repositories.domain.custom_properties.set_properties_for(current_repository.owner, [current_repository], properties, actor: current_user)
      head :ok
    rescue CustomPropertiesCore::Errors::EditPropertyPermissionError => error
      render json: { error: error.full_message }, status: 403
    rescue CustomPropertiesCore::Errors::PropertyValidationError => error
      render json: { error: error.message }, status: 422
    end
  end

  sig { void }
  def suggest_value # rubocop:todo GitHub/UseRestfulActions
    unless FeatureFlag.vexi.enabled?(:suggest_custom_property_values_copilot, current_user, default: false)
      return render json: { error: "Feature not enabled" }, status: :unprocessable_entity
    end

    property_name = params[:propertyName]
    return render json: { error: "propertyName is required" }, status: :bad_request if property_name.blank?

    definition = Repositories.domain.custom_properties.get_definition(current_repository.owner, property_name)
    return render json: { error: "Property not found" }, status: :not_found unless definition

    copilot_api = Copilot::User.copilot_api(
      user: current_user,
      integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
      session: user_session,
      real_ip: request&.remote_ip,
    )

    suggester = RepositoriesCustomProperties::CopilotValueSuggester.new(
      repository: current_repository,
      definition: definition,
      copilot_api: copilot_api,
    )

    render json: { suggestion: suggester.suggest }
  rescue RepositoriesCustomProperties::CopilotValueSuggester::GenerationError
    render json: { error: "Failed to generate suggestion" }, status: :unprocessable_entity
  end

  private

  sig { returns(T.untyped) }
  def ensure_owner_is_org
    render_404 unless current_repository.owner.organization?
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
