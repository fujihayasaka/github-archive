# typed: true
# frozen_string_literal: true

class Stafftools::CodespacesController < StafftoolsController
  layout "layouts/stafftools/user/content"

  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Permissions,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  def index
    render "stafftools/codespaces/index", locals: { active_codespaces: codespaces, deleted_codespaces: deleted_codespaces }
  end

  def show
    codespace = codespaces.include_deleted.find_by!(name: params[:id])
    render "stafftools/codespaces/show", locals: { codespace: codespace }
  end

  def refresh_environment_data # rubocop:todo GitHub/UseRestfulActions
    codespace = codespaces.find_by!(name: params[:id])
    Codespaces::BackfillEnvironmentDataJob.perform_now(codespace: codespace)
    redirect_to stafftools_user_codespace_path(codespace.owner, codespace), notice: "Environment data synchronized."
  end

  def suspend_environment_component # rubocop:todo GitHub/UseRestfulActions
    codespace = codespaces.find_by!(name: params[:id])

    environment = codespace.environment_data.presence || ::Codespaces::Environment.from_json(::Codespaces::VscsClient.for_codespace(codespace).fetch_environment!(codespace.guid))

    render(Stafftools::Codespaces::SuspendEnvironmentComponent.new(
      codespace: codespace,
      environment: environment
    ), layout: false)

  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue Codespaces::Error => e
    Codespaces::ErrorReporter.report(e, codespace: codespace)
    head :not_found
  end

  def suspend_environment # rubocop:todo GitHub/UseRestfulActions
    codespace = codespaces.find_by!(name: params[:id])

    scheduler = Codespaces::ScheduleEnvironmentSuspension.new(codespace)
    if scheduler.codespace_suspendable?
      scheduler.call
      flash[:notice] = "Starting environment suspension for Codespace #{codespace.safe_display_name}. This operation can take a few minutes."
    else
      flash[:error] = "Environment for Codespace #{codespace.safe_display_name} is already suspended."
    end

    redirect_to action: "index"

  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Could not find Codespace to suspend."
    redirect_to action: "index"
  rescue Codespaces::Error => e
    Codespaces::ErrorReporter.report(e, codespace: codespace)
    flash[:error] = "Could not find environment for Codespace to suspend."
    redirect_to action: "index"
  end

  def deprovision_environment # rubocop:todo GitHub/UseRestfulActions
    codespace = codespaces.find_by!(name: params[:id])
    codespace.deprovision!(reason: Codespace.deletion_reasons[:stafftools_requested])
    redirect_to action: "index"
    flash[:notice] = "Starting environment deprovision for Codespace #{codespace.safe_display_name}. This operation can take a few minutes."
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Could not find Codespace to deprovision."
    redirect_to action: "index"
  rescue Codespaces::Error => e
    Codespaces::ErrorReporter.report(e, codespace: codespace)
    flash[:error] = "Could not deprovision codespace: #{e.message}"
    redirect_to action: "index"
  end

  def restore_environment # rubocop:todo GitHub/UseRestfulActions
    codespace = codespaces.deleted.find_by!(name: params[:id])

    scheduler = Codespaces::ScheduleEnvironmentRestoration.new(codespace)
    begin
      scheduler.call
      flash[:notice] = "Restoring environment for Codespace #{codespace.safe_display_name}. This operation can take a few minutes."
    rescue Codespaces::ScheduleEnvironmentRestoration::UnrestorableEnvironmentError
      flash[:error] = "Environment for Codespace #{codespace.safe_display_name} is not in a restorable state."
    end

    redirect_to action: "index"

  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Could not find Codespace to restore."
    redirect_to action: "index"
  rescue Codespaces::Error => e
    Codespaces::ErrorReporter.report(e, codespace: codespace)
    flash[:error] = "Could not find environment for Codespace to restore."
    redirect_to action: "index"
  end

  def fail_environment # rubocop:todo GitHub/UseRestfulActions
    codespace = codespaces.find_by!(name: params[:id])

    if codespace.provisioning? || codespace.deprovisioning?
      client = Codespaces::VscsClient.for_codespace(codespace)
      codespace.failed!
      client.shutdown_environment(codespace.guid) if codespace.guid
      flash[:notice] = "Starting environment shutdown for Codespace #{codespace.safe_display_name} due to failure. This operation can take a few minutes."
    else
      flash[:error] = "Environment shutdown for Codespace #{codespace.safe_display_name} is not available for codespaces that are not in a provisioning or deprovisioning state"
    end

    redirect_to stafftools_user_codespace_path(codespace.owner, codespace)

  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Could not find Codespace to fail."
    redirect_to stafftools_user_codespace_path(codespace.owner, codespace)
  rescue Codespaces::Error => e
    Codespaces::ErrorReporter.report(e, codespace: codespace)
    flash[:error] = "Could not find environment for Codespace to fail."
    redirect_to stafftools_user_codespace_path(codespace.owner, codespace)
  end

  def deprovision_dependent_codespaces # rubocop:todo GitHub/UseRestfulActions
    Codespaces::DeleteDependentCodespacesJob.perform_later(owner_id: this_user.id, reason: Codespace.deletion_reasons[:stafftools_requested])
    flash[:notice] = "Starting deprovisioning. This operation can take a few minutes."
    redirect_to action: "index"
  end

  def suspend_dependent_codespaces # rubocop:todo GitHub/UseRestfulActions
    Codespaces::SuspendDependentCodespacesJob.perform_later(owner_id: this_user.id)
    flash[:notice] = "Starting suspension. This operation can take a few minutes."
    redirect_to action: "index"
  end

  def bulk_restore_environments # rubocop:todo GitHub/UseRestfulActions
    deletion_reasons = params[:bulk_restore_deletion_reasons]

    Codespaces::BulkRestoreCodespacesJob.perform_later(
      user_id: this_user.id,
      deletion_reasons: deletion_reasons
    )

    flash[:notice] = "Attempting to restore #{deleted_codespaces.count} environments for #{this_user.type.downcase} #{this_user.login}'s Codespaces. This operation can take anywhere from a few minutes to a few hours."
    redirect_to action: "index"
  end

  private

  def codespaces
    Codespace.where(billable_owner: this_user).or(Codespace.where(owner: this_user)).includes(:repository, :owner, :billable_owner)
  end

  def deleted_codespaces
    Codespace.deleted.where(billable_owner: this_user).or(
      Codespace.deleted.where(owner: this_user)
    ).where("deleted_at > ?", 14.days.ago).includes(:repository, :owner, :billable_owner)
  end
end
