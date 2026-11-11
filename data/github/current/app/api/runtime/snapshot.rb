# typed: true
# frozen_string_literal: true

class Api::Runtime::Snapshot < Api::App
  ROUTES_EXCLUDED_FROM_EMU_OWNERSHIP_CAP = [
    ["post", "/runtime/:environment_id/snapshot/"],
  ].freeze

  # Flags the environment as snapshotted, indicating it can be
  # safely deleted since its contents are stored in Azure Blob Storage.
  post "/runtime/:environment_id/snapshot/", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"
    environment_id = params[:environment_id]

    codespace = current_user&.codespaces&.find_by(guid: environment_id) do |scope|
      scope.visible_to_ephemeral_cloud_environments(current_user) |
      scope.visible_to_workbench_cloud_environments(current_user)
    end

    if !codespace || codespace&.environment_data.state == Codespaces::Vscs::State::SHUTDOWN
      deliver_error! 404
    end

    control_access :read_codespace,
      codespace:,
      resource: codespace.repository,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    workbench = T.must(Spark::Workbench.for_cloud_environment_id(codespace.id))
    workbench.update!(last_snapshot_environment_id: codespace.id)

    deliver_raw({ status: "success" })
  end

  # Skip EMU ownership enforcement for Spark EMU codespaces accessing the spark-template repo
  def emu_ownership_enforceable
    return :yes unless ROUTES_EXCLUDED_FROM_EMU_OWNERSHIP_CAP.include?(
      [request.request_method.downcase, route_pattern]
    )

    # Check if this is a Spark EMU scenario that should bypass ownership checks
    if current_user&.feature_flag_enabled?(:spark_emu_bypass_ownership_cap, default: false) &&
       current_user&.is_enterprise_managed? &&
       params[:environment_id] &&
       (codespace = current_user.codespaces.visible_to_workbench_cloud_environments(current_user).find_by(guid: params[:environment_id]))
      return :no if Codespaces::SparkEmu.is_spark_emu?(current_user, codespace.repository)
    end

    :yes
  end
end
