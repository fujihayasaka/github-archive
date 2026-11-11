# typed: strict
# frozen_string_literal: true

module Orca
  module OrcaControllerHelper
    extend T::Helpers

    include GitHub::Memoizer
    include OrganizationsHelper

    requires_ancestor { ApplicationController }

    abstract!

    sig { returns(T::Array[Orca::Pipeline::LinguistLangHash]) }
    memoize def available_languages
      Linguist::Language.all.map { |lang| { name: lang.name, color: lang.color, id: lang.language_id } }
    end

    sig { returns(T.nilable(Orca::Pipeline)) }
    memoize def current_pipeline
      pipeline = Orca::Pipeline.fetch_by_id(params[:pipeline_id])
      return if pipeline.nil?
      pipeline
    end

    sig { void }
    def check_pipeline_access
      if current_pipeline.nil? || T.must(current_pipeline).organization.id != current_organization.id
        raise ActionController::RoutingError.new("Not Found")
      end
    end

    sig { void }
    def rate_limit
      return if within_rate_limit?
      redirect_to index_path
    end

    sig do returns({
    copilot_private_telemetry_access: T::Boolean
    })
    end
    def feature_flags
      {
        copilot_private_telemetry_access: feature_enabled?(:copilot_private_telemetry_access),
      }
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def feature_enabled?(feature)
      current_user&.feature_flag_enabled_or_raise?(feature) || current_organization.feature_flag_enabled_or_raise?(feature) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { void }
    def feature_required
      render_404 unless feature_enabled?(:copilot_custom_models)
    end

    sig { returns(T::Boolean) }
    memoize def within_rate_limit?
      orca_rate_limit.within_rate_limit?
    end

    sig { returns(T.nilable(String)) }
    memoize def rate_limit_reset_at
      orca_rate_limit.reset_at
    end

    sig { returns(Orca::RateLimit) }
    memoize def orca_rate_limit
      Orca::RateLimit.new(current_organization)
    end

    sig { returns(T.nilable(Orca::Pipeline)) }
    memoize def latest_completed_pipeline
      latest_completed_pipeline!
    end

    sig { returns(T.nilable(Orca::Pipeline)) }
    def latest_completed_pipeline!
      Orca::Pipeline.latest_completed_pipeline(current_organization)
    end

    sig { returns(T.nilable(Orca::Pipeline)) }
    memoize def latest_pipeline
      latest_pipeline!
    end

    sig { returns(T.nilable(Orca::Pipeline)) }
    def latest_pipeline!
      Orca::Pipeline.latest_pipeline(current_organization)
    end

    sig { params(pipeline: Orca::Pipeline).returns(T::Boolean) }
    def deployed_pipeline?(pipeline)
      return false if latest_completed_pipeline.nil?

      latest = T.must(latest_completed_pipeline)
      latest.pipeline_id == pipeline.pipeline_id
    end

    Actor = T.type_alias do
      { avatarUrl: T.nilable(String), login: T.nilable(String) }
    end

    # When modifying this, modify `pipeline_details_as_json` too
    sig do params(pipeline: Orca::Pipeline).returns({
      id: String,
      actorLogin: T.nilable(String),
      cancelPath: String,
      createdAt: T.nilable(String),
      destroyPath: String,
      editPath: String,
      isDeployed: T::Boolean,
      repositoryCount: Integer,
      showPath: String,
      status: String,
    })
    end
    def pipeline_item_as_json(pipeline)
      base = pipeline.as_json
      pipeline_id = pipeline.pipeline_id

      {
        id: base[:id],
        actorLogin: pipeline.actor_login,
        cancelPath: cancel_path(pipeline_id),
        createdAt: base[:createdAt],
        destroyPath: destroy_path(pipeline_id),
        editPath: edit_path(pipeline_id),
        isDeployed: deployed_pipeline?(pipeline),
        repositoryCount: base[:repositoryCount],
        showPath: show_path(pipeline_id),
        status: base[:status]
      }
    end

    # This signature must extend the `pipeline_item_as_json` signature
    sig do params(pipeline: Orca::Pipeline).returns({
      id: String,
      actorLogin: T.nilable(String),
      actorAvatarUrl: T.nilable(String),
      cancelPath: String,
      createdAt: T.nilable(String),
      destroyPath: String,
      editPath: String,
      isDeployed: T::Boolean,
      languages: T::Array[Orca::Pipeline::LinguistLangHash],
      repoSearchPath: String,
      repositoryCount: Integer,
      showPath: String,
      stages: T::Array[Orca::PipelineLogs::Stage],
      status: String,
      wasPrivateTelemetryCollected: T::Boolean,
    })
    end
    def pipeline_details_as_json(pipeline)
      base = pipeline.as_json
      item = pipeline_item_as_json(pipeline)

      actor = pipeline.actor
      avatar_url = actor.present? ? T.cast(actor.primary_avatar_url, String) : nil

      details = {
        actorAvatarUrl: avatar_url,
        languages: base[:languages],
        repoSearchPath: repo_search_path(pipeline.pipeline_id),
        stages: base[:stages],
        wasPrivateTelemetryCollected: base[:wasPrivateTelemetryCollected]
      }

      # Make sure to extend the base item to align with the UI and DRY up UI types
      item.merge(details)
    end

    sig { returns(String) }
    def admin_email
      current_user&.email
    end

    sig { returns(T::Boolean) }
    def any_deployed?
      !!latest_completed_pipeline
    end

    sig { params(pipeline_id: String).returns(String) }
    def cancel_path(pipeline_id)
      settings_org_copilot_custom_models_cancel_path(current_organization, pipeline_id)
    end

    sig { returns(String) }
    def create_path
      settings_org_copilot_custom_models_create_path(current_organization)
    end

    sig { params(pipeline_id: String).returns(String) }
    def destroy_path(pipeline_id)
      settings_org_copilot_custom_models_destroy_path(current_organization, pipeline_id)
    end

    sig { params(pipeline_id: String).returns(String) }
    def edit_path(pipeline_id)
      settings_org_copilot_custom_models_edit_path(current_organization, pipeline_id)
    end

    sig { returns(String) }
    def index_path
      settings_org_copilot_custom_models_path(current_organization)
    end

    sig { returns(String) }
    def new_path
      settings_org_copilot_custom_models_new_path(current_organization)
    end

    sig { params(pipeline_id: String).returns(String) }
    def show_path(pipeline_id)
      settings_org_copilot_custom_model_trainings_show_path(current_organization, pipeline_id)
    end

    sig { params(pipeline_id: String).returns(String) }
    def repo_list_path(pipeline_id)
      settings_org_copilot_custom_model_pipeline_repositories_path(current_organization, pipeline_id)
    end

    sig { params(pipeline_id: String).returns(String) }
    def repo_search_path(pipeline_id)
      settings_org_copilot_custom_model_pipeline_repositories_search_path(current_organization, pipeline_id)
    end

    sig { returns(String) }
    def policy_path
      settings_org_copilot_policies_path(current_organization)
    end
  end
end
