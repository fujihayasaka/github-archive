# typed: true
# frozen_string_literal: true

class Memexes::AutoAssignAgentConfigurationsController < Memexes::Controller
  include ApplicationController::VerifiedFetchDependency

  CONFIGURED_MODEL_UNAVAILABLE_NOTICE = "The configured model is no longer available. Future auto-assign runs will use the default model."
  METRICS_SURFACE = "internal_auto_assign_api"
  METRICS_SURFACE_TAG = "surface:#{METRICS_SURFACE}"

  before_action :login_required, except: [:index]
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :require_this_workflow, only: [:update, :destroy]
  before_action :user_has_read_access, only: [:index]
  before_action :user_has_write_access, except: [:index]
  before_action :require_verified_email, except: [:index]
  before_action :set_client_uid

  allow_verified_fetch only: [:create, :update, :destroy]

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::AutoAssignAgentConfigurationsController#create",
    "Memexes::AutoAssignAgentConfigurationsController#update",
    "Memexes::AutoAssignAgentConfigurationsController#destroy",
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Configurations,
    only: [:index],
    optional: true

  def index
    workflows = this_memex.workflows.where(trigger_type: :auto_assign_agent).includes(:actions)
    render(json: { autopilotConfigurations: workflows.map { |workflow| workflow_configuration_hash(workflow) } })
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:create]

  def create
    workflow = this_memex.workflows.create(**create_workflow_params)

    if workflow.valid? && workflow.persisted?
      # Instrument the create event
      GlobalInstrumenter.instrument "memex_event", {
        actor: current_user,
        memex_project: this_memex,
        name: "auto_assign_agent_configuration_created",
        context: {
          workflow_id: workflow.id,
          surface: METRICS_SURFACE,
        }.to_json,
      }

      GitHub.dogstats.increment(
        "memex.auto_assign_agent_configuration.create.success",
        tags: [
          METRICS_SURFACE_TAG,
        ]
      )

      render(json: { workflow: workflow.to_hash }, status: :created)
    else
      error_count = workflow.errors.full_messages.count

      GitHub.dogstats.increment(
        "memex.auto_assign_agent_configuration.create.error",
        tags: [
          METRICS_SURFACE_TAG,
        ]
      )

      GitHub.dogstats.distribution(
        "memex.auto_assign_agent_configuration.create.error_count",
        error_count,
        tags: [
          METRICS_SURFACE_TAG,
        ]
      )

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
      # Instrument the update event
      GlobalInstrumenter.instrument "memex_event", {
        actor: current_user,
        memex_project: this_memex,
        name: "auto_assign_agent_configuration_updated",
        context: {
          workflow_id: this_workflow.id,
          enabled: this_workflow.enabled,
          surface: METRICS_SURFACE,
        }.to_json,
      }

      GitHub.dogstats.increment(
        "memex.auto_assign_agent_configuration.update.success",
        tags: [
          METRICS_SURFACE_TAG,
          "enabled:#{this_workflow.enabled}",
        ]
      )

      render(json: { workflow: this_workflow.to_hash })
    else
      error_count = this_workflow.errors.full_messages.count

      GitHub.dogstats.increment(
        "memex.auto_assign_agent_configuration.update.error",
        tags: [
          METRICS_SURFACE_TAG,
        ]
      )

      GitHub.dogstats.distribution(
        "memex.auto_assign_agent_configuration.update.error_count",
        error_count,
        tags: [
          METRICS_SURFACE_TAG,
        ]
      )

      render(json: { errors: this_workflow.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:destroy]

  def destroy
    if this_workflow.destroy
      # Instrument the destroy event
      GlobalInstrumenter.instrument "memex_event", {
        actor: current_user,
        memex_project: this_memex,
        name: "auto_assign_agent_configuration_destroyed",
        context: {
          workflow_id: this_workflow.id,
          surface: METRICS_SURFACE,
        }.to_json,
      }

      GitHub.dogstats.increment(
        "memex.auto_assign_agent_configuration.destroy.success",
        tags: [
          METRICS_SURFACE_TAG,
        ]
      )

      head :no_content
    elsif this_workflow.errors.any?
      error_count = this_workflow.errors.full_messages.count

      GitHub.dogstats.increment(
        "memex.auto_assign_agent_configuration.destroy.error",
        tags: [
          METRICS_SURFACE_TAG,
        ]
      )

      GitHub.dogstats.distribution(
        "memex.auto_assign_agent_configuration.destroy.error_count",
        error_count,
        tags: [
          METRICS_SURFACE_TAG,
        ]
      )

      render(json: { errors: this_workflow.errors.full_messages }, status: :unprocessable_entity)
    else
      GitHub.dogstats.increment(
        "memex.auto_assign_agent_configuration.destroy.error",
        tags: [
          METRICS_SURFACE_TAG,
          "error:unknown",
        ]
      )

      head :bad_request
    end
  end

  private

  def require_this_workflow
    render_404 unless this_workflow
  end

  memoize def this_workflow
    this_memex.workflows
      .where(trigger_type: :auto_assign_agent)
      .find_by(number: underscored_params[:workflow_number])
  end

  def create_workflow_params
    ap = underscored_params.require(:autopilot_configuration)

    {
      name: ap[:name].presence || MemexProjectWorkflow::DEFAULT_NAME_BY_TRIGGER_TYPE[:auto_assign_agent],
      trigger_type: :auto_assign_agent,
      enabled: ap[:enabled].nil? ? false : ap[:enabled],
      content_types: MemexProjectWorkflow::CONTENT_TYPE_CONSTRAINTS_BY_TRIGGER_TYPE[:auto_assign_agent],
      creator: current_user,
      last_updater: current_user,
      actions_attributes: [
        {
          action_type: :get_project_items,
          creator: current_user,
          arguments: {
            "fieldId" => ap[:field_id],
            "fieldOptionId" => ap[:field_option_id],
          },
        },
        {
          action_type: :assign_copilot,
          creator: current_user,
          arguments: assign_copilot_arguments(ap),
        },
      ],
    }
  end

  def update_workflow_params
    ap = underscored_params.except(:workflow_number)

    update_hash = { last_updater: current_user }
    update_hash[:enabled] = ap[:enabled] unless ap[:enabled].nil?
    update_hash[:name] = ap[:name] if ap[:name].present?

    if has_action_updates?(ap)
      update_hash[:actions_attributes] = build_update_actions(ap)
    end

    update_hash
  end

  def has_action_updates?(ap)
    ap.key?(:instruction) ||
      ap.key?(:destination_field_option_id) ||
      ap.key?(:output_mode) ||
      ap.key?(:model) ||
      ap.key?(:allowed_repositories) ||
      ap[:field_id].present? ||
      ap[:field_option_id].present?
  end

  def build_update_actions(ap)
    actions = []
    get_items_action = this_workflow.actions.find_by(action_type: :get_project_items)
    assign_action = this_workflow.actions.find_by(action_type: :assign_copilot)

    if get_items_action && (ap[:field_id].present? || ap[:field_option_id].present?)
      new_args = get_items_action.arguments.dup
      new_args["fieldId"] = ap[:field_id].to_i if ap[:field_id].present?
      new_args["fieldOptionId"] = ap[:field_option_id] if ap[:field_option_id].present?
      actions << { id: get_items_action.id, arguments: new_args, last_updater: current_user }
    end

    if assign_action && (ap.key?(:instruction) || ap.key?(:destination_field_option_id) || ap.key?(:output_mode) || ap.key?(:model) || ap.key?(:allowed_repositories))
      new_args = assign_action.arguments.dup
      new_args["instruction"] = ap[:instruction] if ap.key?(:instruction)
      new_args["destinationFieldOptionId"] = ap[:destination_field_option_id] if ap.key?(:destination_field_option_id)
      new_args["outputMode"] = ap[:output_mode] if ap.key?(:output_mode)
      new_args["model"] = ap[:model] if ap.key?(:model)
      new_args["allowedRepositories"] = ap[:allowed_repositories] if ap.key?(:allowed_repositories)
      actions << { id: assign_action.id, arguments: new_args, last_updater: current_user }
    end

    actions
  end

  def assign_copilot_arguments(ap)
    args = {}
    args["instruction"] = ap[:instruction] if ap[:instruction].present?
    args["destinationFieldOptionId"] = ap[:destination_field_option_id] if ap[:destination_field_option_id].present?
    args["outputMode"] = ap[:output_mode] if ap[:output_mode].present?
    args["agentId"] = ap[:agent_id] if ap[:agent_id].present?
    args["model"] = ap[:model] if ap[:model].present?
    args["allowedRepositories"] = ap[:allowed_repositories] if ap[:allowed_repositories].present?
    args
  end

  def workflow_configuration_hash(workflow)
    config = workflow.to_hash
    model = configured_model(config)
    return config unless configured_model_unavailable?(model)

    config[:notices] = [
      {
        type: "configured_model_unavailable",
        message: CONFIGURED_MODEL_UNAVAILABLE_NOTICE,
        model: model,
      },
    ]
    config
  end

  def configured_model(config)
    assign_action = config[:actions]&.find { |action| action[:actionType] == "assign_copilot" }
    assign_action&.dig(:arguments, "model").presence
  end

  def configured_model_unavailable?(model)
    model.present? && available_model_keys.exclude?(model)
  end

  memoize def available_model_keys
    copilot_entity = case owner = this_memex.owner
    when User
      Copilot::User.new(owner)
    when Organization
      Copilot::Organization.new(owner)
    end

    return [] unless copilot_entity
    Copilot::ModelsRegistryCache.for_entity(copilot_entity).filter_map(&:model_key)
  end
end
