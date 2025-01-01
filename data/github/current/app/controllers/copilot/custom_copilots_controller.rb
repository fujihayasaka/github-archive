# typed: true
# frozen_string_literal: true

class Copilot::CustomCopilotsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :require_feature_enabled
  before_action :login_required
  before_action :parse_json_params, only: [:create, :update]
  allow_verified_fetch only: [:create, :update, :destroy]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
  only: [:new, :edit, :share]

  self.react_bundle_name = "custom-copilots"

  def new
    context_region_title "New Copilot Space"

    custom_copilot = CustomCopilot.new(
      owner: current_user,
    )

    render_react_app payload: {
      findFileWorkerPath: helpers.find_file_worker_path,
      customCopilot: {
        id: nil,
        name: nil,
        description: nil,
        resources: [],
        generalInstructions: nil,
      },
      ssoOrganizations: sso_orgs,
    }, title: "New Copilot Space"
  end

  def create
    custom_copilot = CustomCopilot.new(create_custom_copilot_params)
    custom_copilot.owner = current_user
    custom_copilot.current_user = current_user
    custom_copilot.cap_filter = cap_filter


    if custom_copilot.save
      instrument_hydro_events(:create, custom_copilot)
      render json: {
        id: custom_copilot.id,
        name: custom_copilot.name,
        slug: custom_copilot.slug,
        updatedAt: custom_copilot.updated_at,
        description: custom_copilot.description,
        generalInstructions: custom_copilot.general_instructions,
        primaryAvatarPath: custom_copilot.primary_avatar_path,
        slugWithOwner: custom_copilot.slug_with_owner,
        resources: custom_copilot.resources_react_payload(viewer: current_user, cap_filter:),
      }, status: :ok
    else
      render json: { errorMessages: format_error_messages(custom_copilot.errors) }, status: :unprocessable_entity
    end
  end

  def edit
    context_region_title "Edit Copilot Space"

    render_react_app payload: {
      findFileWorkerPath: helpers.find_file_worker_path,
      customCopilot: {
        id: custom_copilot.id,
        name: custom_copilot.name,
        description: custom_copilot.description,
        generalInstructions: custom_copilot.general_instructions,
        resources: custom_copilot.resources_react_payload(viewer: current_user, cap_filter:),
      },
      ssoOrganizations: sso_orgs,
    }, title: "Edit Copilot Space"
  end

  def update
    custom_copilot.assign_attributes(update_custom_copilot_params)
    custom_copilot.current_user = current_user
    custom_copilot.cap_filter = cap_filter

    if custom_copilot.save
      instrument_hydro_events(:update, custom_copilot)
      render json: {
        id: custom_copilot.id,
        name: custom_copilot.name,
        slug: custom_copilot.slug,
        updatedAt: custom_copilot.updated_at,
        description: custom_copilot.description,
        generalInstructions: custom_copilot.general_instructions,
        primaryAvatarPath: custom_copilot.primary_avatar_path,
        slugWithOwner: custom_copilot.slug_with_owner,
        resources: custom_copilot.resources_react_payload(viewer: current_user, cap_filter:),
      }, status: :ok
    else
      render json: { errorMessages: format_error_messages(custom_copilot.errors) }, status: :unprocessable_entity
    end
  end

  # rubocop:todo GitHub/UseRestfulActions

  def share
    context_region_title "Shared Copilot Space"

    custom_copilot = CustomCopilot.find(params[:id])
    instrument_hydro_events(:share, custom_copilot)
    render_react_app payload: {
      findFileWorkerPath: helpers.find_file_worker_path,
      customCopilot: {
        name: custom_copilot.name,
        description: custom_copilot.description,
        generalInstructions: custom_copilot.general_instructions,
        resources: custom_copilot.resources_react_payload(viewer: current_user, cap_filter:)
      },
      ssoOrganizations: sso_orgs,
    }, title: "Shared Copilot Space"
  end

  def destroy
    if custom_copilot.destroy
      instrument_hydro_events(:delete, custom_copilot)
      flash[:notice] = "Copilot Space deleted"
      redirect_to copilot_spaces_list_path
    else
      flash[:error] = "Copilot Space could not be deleted"
    end
  end

  private

  memoize def show_search_form?
    user_feature_enabled?(:copilot_custom_copilots_search)
  end

  def format_error_messages(errors)
    errors.messages.transform_values do |error_messages|
      # This converts the error messages from an array of strings, to a single
      # string sentence for easy display in the UI
      error_messages.to_sentence
    end
  end

  # Returns a hash where the keys are custom copilot ids and the values are arrays of resources
  def visible_resources_for_viewer(custom_copilot_ids)
    resources = CustomCopilotResource.where(custom_copilot_id: custom_copilot_ids).to_a

    repository_resources, other_resources = resources.partition do |resource|
      resource.github_file_resource_type?
    end

    repos = Repositories::Public.load_repositories(repository_resources.map(&:repository_id))
    visible_repos_indexed_by_id = cap_filter.authorized(repos).results.map(&:resource).filter do |repo|
      repo.readable_by?(current_user)
    end.index_by(&:id)

    visible_repository_resources = repository_resources.select do |resource|
      visible_repos_indexed_by_id.key?(resource.repository_id)
    end

    (visible_repository_resources + other_resources).group_by(&:custom_copilot_id)
  end

  memoize def custom_copilot
    CustomCopilot.where(owner: current_user).find(params[:id])
  end

  memoize def sso_orgs
    saml_for_user.protected_organizations.map { |org| { id: org.id.to_s, name: org.name, login: org.display_login } }
  end

  def require_feature_enabled
    render_404 unless user_feature_enabled?(:copilot_custom_copilots)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def update_custom_copilot_params
    params
      .require(:custom_copilot)
      .permit(:name,
        :description,
        :general_instructions,
        resources_attributes: [
          :_destroy,
          :id,
          :resource_type,
          { metadata:
            [
              :repository_id,
              :file_path,
              :text,
              :name,
              ]
            }
          ])
  end

  def create_custom_copilot_params
    update_custom_copilot_params.tap do |params|
      if params[:resources_attributes]
        params[:resources_attributes].each do |resource|
          resource.delete(:id)
        end
      end
    end
  end

  def event(action, custom_copilot)
    {
      custom_copilot_id: custom_copilot.id,
      custom_copilot_uuid: custom_copilot.uuid || "",
      total_size: custom_copilot.total_content_size,
      user_analytics_tracking_id: current_user.analytics_tracking_id,
      action: action,
      instructions_size: custom_copilot.general_instructions&.size&.to_i,
    }
  end

  def restricted_event(action, custom_copilot)
    restricted_fields = {
      name: custom_copilot.name,
      description: custom_copilot.description,
      resources: custom_copilot_resources(custom_copilot),
      instructions: custom_copilot.general_instructions,
    }

    event(action, custom_copilot).merge(restricted_fields)
  end

  def custom_copilot_resources(custom_copilot)
    custom_copilot.resources.map do |resource|
      {
        name: resource.file_name,
        type: resource.resource_type,
        size: resource.size,
      }
    end
  end

  def instrument_hydro_events(action, custom_copilot)
    return unless user_feature_enabled?(:copilot_custom_copilots_hydro_events)

    action = action.to_s.upcase
    custom_copilot.current_user = current_user if custom_copilot.current_user.nil?
    custom_copilot.cap_filter = cap_filter if custom_copilot.cap_filter.nil?
    GlobalInstrumenter.instrument("custom_copilot.event", event(action, custom_copilot))
    GlobalInstrumenter.instrument("custom_copilot.restricted_event", restricted_event(action, custom_copilot))
  end
end
