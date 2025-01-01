# typed: true
# frozen_string_literal: true

class Api::Runtime::Snapshot < Api::App

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
end
