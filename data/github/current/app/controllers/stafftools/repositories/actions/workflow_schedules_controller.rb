# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::WorkflowSchedulesController < StafftoolsController
  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    return render_404 unless GitHub.actions_enabled?

    result = Launch::Twirp.deployer_client.list_schedules(current_repository)
    error_message = "Error fetching workflow schedules" unless result.call_succeeded?

    if error_message.nil?
      workflow_schedule_data = build_workflow_schedule_data(result.value)
    else
      workflow_schedule_data = []
      flash[:error] = error_message
    end

    render "stafftools/repositories/actions/workflow_schedules", locals: {
      repository: current_repository,
      workflow_schedule_data: workflow_schedule_data,
      workflow_schedule_data_count: workflow_schedule_data.count
    }
  end

  def resync # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled? && current_repository.actions_enabled?

    result = Launch::Twirp.deployer_client.synchronize_scheduled_workflows(current_repository, current_repository.owner)

    if result.call_succeeded?
      flash[:notice] = "Synced repository workflows."
    else
      flash[:error] = "Error syncing repository workflows."
    end

    redirect_to actions_workflow_schedules_stafftools_repository_path
  end

  def update
    return render_404 unless GitHub.actions_enabled? && current_repository.actions_enabled?

    error_message = nil

    workflow_file_path = URI::decode_www_form_component(params.require(:workflow_file_path))
    actor_login = params[:actor_login]
    error_message = "No actor entered" unless actor_login.present?

    if error_message.nil?
      actor = User.find_by_login(actor_login)
      error_message = "Recreate failed. Actor '#{actor_login}' does not have write permissions for the repository." unless current_repository.writable_by?(actor)
    end

    if error_message.nil? && actor.disabled?
      error_message = "Recreate failed. Actor '#{actor_login}' is disabled."
    end

    if error_message.nil? && actor.spammy?
      error_message = "Recreate failed. Actor '#{actor_login}' is marked as spammy."
    end

    if error_message.nil? && actor.no_verified_emails?
      error_message = "Recreate failed. Actor '#{actor_login}' does not have a verified email address."
    end

    if error_message.nil?
      result = Launch::Twirp.deployer_client.disable_scheduled_workflow(current_repository, workflow_file_path)
      error_message = "Error disabling workflow schedule." unless result.call_succeeded?
    end

    if error_message.nil?
      result = Launch::Twirp.deployer_client.synchronize_scheduled_workflows(current_repository, actor)
      error_message = "Error syncing repository workflows. Please click the 'Resync schedules' button." unless result.call_succeeded?
    end

    if error_message.nil?
      flash[:notice] = "Recreated workflow schedule."
    else
      flash[:error] = error_message
    end

    redirect_to actions_workflow_schedules_stafftools_repository_path
  end

  private

  sig { params(value: GitHub::Launch::Pbtypes::Deploy::ListSchedulesResponse).returns(T::Array[Data]) }
  def build_workflow_schedule_data(value)
    workflow_data = Data.define(:schedule, :actor)

    # The ListSchedules API will only return a maximum of 100 records, so we can lookup all the actors with one query
    actors_to_schedule = value.workflow_schedules.map do |workflow_schedule|
      # [0] is the entity type, [1] is the database id
      database_id = Platform::Helpers::NodeIdentification.from_global_id(workflow_schedule.actor_next_id.global_id)[1]&.to_i
      [database_id, workflow_schedule]
    end
    actors = User.where(id: actors_to_schedule.map(&:first).uniq).index_by(&:id)

    workflow_schedule_data = actors_to_schedule.map do |actor_id, workflow_schedule|
      workflow_data.new(
        schedule: workflow_schedule,
        actor: actors[actor_id],
      )
    end

    workflow_schedule_data.sort_by! { |data| data.schedule.workflow_file_path }
  end
end
