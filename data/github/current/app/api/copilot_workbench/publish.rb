# typed: true
# frozen_string_literal: true

class Api::CopilotWorkbench::Publish < Api::App
  include FeatureFlagHelper

  before do
    deliver_error!(404) unless current_user&.spark_enabled?
  end

  # Create and assign a repository for a repo-less workbench + codespace pair.
  post "/copilot_workbench/:codespace_name/publish", operation_id: :internal, read_from_replicas: true do
    deliver_error! 404 unless GitHub.codespaces_enabled?

    # If the codespace exists and the caller knows the name then there's no need to hide it. If they don't have
    # access then authz will fail below.
    codespace = current_user&.codespaces.find_by(name: params[:codespace_name])

    # We share the typical Codespace publication access checking.
    # Spark-specifics are handled here in the endpoint implementation.
    control_access :publish_codespace_public,
      resource: codespace,
      challenge: true,
      forbid: codespace.present?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error! 404, message: "No workbench found for with that codespace" unless codespace.spark_workbench_id

    workbench = Spark::Workbench.for_uuid_string(current_user.id, codespace.spark_workbench_id)
    if workbench && workbench.repository
      repo = T.must(workbench.repository)
      halt deliver_raw({
        success: false,
        existed: true,
        id: repo.id,
        fullName: repo.name_with_display_owner,
        url: repo.gitweb_url_for_api,
        cloneUrl: repo.clone_url_for_api,
      }, status: 422)
    end

    data = receive_with_openapi

    result = with_write(clusters: [
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::Repositories,
    ]) do
      Codespaces::PublishToRepository.call(
        codespace:,
        name: data["name"],
        is_private: true,
      )
    end

    if result.success?
      deliver_raw({
        success: true,
        id: result.repository.id,
        fullName: result.repository.full_name,
        url: result.repository.permalink,
        cloneUrl: result.repository.clone_url,
      }, status: :created)
    else
      deliver_error 422, message: result.reason
    end
  end
end
