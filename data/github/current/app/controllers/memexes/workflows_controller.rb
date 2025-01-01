# typed: true
# frozen_string_literal: true

class Memexes::WorkflowsController < Memexes::Controller
  include MemexesHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required, except: [:defaults, :index]
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :require_this_workflow, only: [:update]
  before_action :user_has_read_access, only: [:defaults, :index]
  before_action :user_has_write_access, except: [:defaults, :index]
  before_action :require_verified_email, except: [:defaults, :index]
  before_action :set_client_uid

  allow_verified_fetch only: [:create, :update]

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::WorkflowsController#create",
    "Memexes::WorkflowsController#update"
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex

  depends_on_clusters ApplicationRecord::Collab,
    only: [:defaults, :index]

  depends_on_clusters ApplicationRecord::Configurations,
    only: [:defaults]

  def defaults # rubocop:todo GitHub/UseRestfulActions
    render(json: { workflows: this_memex.default_workflows.map(&:to_hash) })
  end

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Configurations,
    only: [:index],
    optional: true

  def index
    render(json: { workflows: this_memex.workflows.map(&:to_hash) })
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:create]

  def create
    workflow = this_memex.workflows.create(**create_workflow_params)

    if workflow.valid? && workflow.persisted?
      if should_trigger_manual_run?(created_workflow: workflow)
        MemexProjectWorkflowRunnerJob.perform_later(
          workflow_id: workflow.id,
          input: nil,
          actor_id: workflow.creator.id,
          event_time: workflow.created_at,
          manual_run: true
        )
      end
      render(json: { workflow: workflow.to_hash }, status: :created)
    else
      render(json: { errors: workflow.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:update]

  def update
    if this_workflow.update(**update_workflow_params)
      if should_trigger_manual_run?
        MemexProjectWorkflowRunnerJob.perform_later(
          workflow_id: this_workflow.id,
          input: nil,
          actor_id: this_workflow.last_updater.id,
          event_time: this_workflow.updated_at,
          manual_run: true
        )
      end
      render(json: { workflow: this_workflow.to_hash })
    else
      render(json: { errors: this_workflow.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  private def require_this_workflow
    render_404 unless this_workflow
  end

  private def this_workflow # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @this_workflow if defined?(@this_workflow)
    @this_workflow = this_memex.workflows.find_by(number: underscored_params[:workflow_number])
  end

  private def create_workflow_params # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @create_workflow_params if defined?(@create_workflow_params)
    @create_workflow_params = create_workflow_top_level_params.merge(create_workflow_actions_params)
  end
  # We retrieve the underscored versions of these params so that we can pass them directly to the
  # MemexProjectWorkflow#create method.
  private def create_workflow_top_level_params
    underscored_params
      .require(:workflow)
      .except(:actions)
      .permit(
        :name,
        :trigger_type,
        :enabled,
        content_types: [],
      )
      .merge(creator: current_user, last_updater: current_user)
  end

  # We massage these parameters to produce the right casing before we pass them to
  # MemexProjectWorkflow#create. Specifically, the keys within the `arguments` are left in
  # camel-case (since they're stored as JSON), but the other keys are underscored.
  private def create_workflow_actions_params
    actions_params = params.require(:workflow).slice(:actions).permit(
      actions: [
        :actionType,
        arguments: [
          :fieldId,
          :fieldOptionId,
          :query,
          :repositoryId,
          :subIssue
        ]
      ]
    )

    if actions_params[:actions].present?
      actions_params[:actions_attributes] = actions_params.delete(:actions)
      actions_params[:actions_attributes].each do |attributes|
        attributes[:action_type] = attributes.delete(:actionType)
        attributes[:creator] = current_user
        attributes[:last_updater] = current_user
      end
    end

    actions_params
  end

  # We massage these parameters to produce the right casing before we pass them to
  # MemexProjectWorkflow#update. Specifically, the keys within the `arguments` are left in
  # camel-case (since they're stored as JSON), but the other keys are underscored.
  private def update_workflow_actions_params
    actions_params = params.slice(:actions).permit(
      actions: [
        :id,
        :actionType,
        arguments: [
          :fieldId,
          :fieldOptionId,
          :query,
          :repositoryId,
          :subIssue
        ]
      ]
    )

    if actions_params[:actions].present?
      actions_params[:actions_attributes] = actions_params.delete(:actions)
      actions_params[:actions_attributes].each do |attributes|
        if attributes[:actionType].present?
          attributes[:action_type] = attributes.delete(:actionType)
        end
        attributes[:last_updater] = current_user
      end
    end

    actions_params
  end

  private def update_workflow_params
    underscored_params
      .except(:actions)
      .permit(
        # These params are only used for routing, but we must `permit` them in
        # alongside the params we actually care about.
        :org,
        :memex_number,
        :memex_id,
        :workflow_number,

        # Allow the workflow's name to be updated
        :name,

        # This is actually used to update a workflow via the `update` endpoint.
        :enabled,

        # allowing :content_types as well as content_types: [] allows us to pass
        # things like nil content_types to the model validations, giving
        # more fine grained controls over what validation errors look like
        :content_types,
        content_types: []
      )
      .slice(:enabled, :name, :content_types)
      .merge(last_updater: current_user)
      .merge(update_workflow_actions_params)
  end

  private def should_trigger_manual_run?(created_workflow: nil)
    workflow_to_run = created_workflow || this_workflow
    workflow_to_run.enabled? && workflow_to_run.allow_manual_run?
  end
end
