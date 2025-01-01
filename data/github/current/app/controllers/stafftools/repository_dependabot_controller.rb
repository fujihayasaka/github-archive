# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryDependabotController < Stafftools::RepositoriesController
  include Secrets::Helper

  before_action :ensure_dependabot_available
  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    response = list_update_configs
    render "stafftools/repository_dependabot/show",
      locals: { update_configs: response.update_configs, dependabot_secrets: dependabot_secrets }
  rescue Dependabot::Twirp::ServiceUnavailableError
    render "stafftools/repository_dependabot/unavailable"
  rescue Dependabot::Twirp::Error => error
    render "stafftools/repository_dependabot/error", locals: { error: error }
  end

  def debug_update_config # rubocop:todo GitHub/UseRestfulActions
    # debug action only permitted if stafftools users has read access. This is
    # to require that a user has requested access to a user's private
    # repository prior to debugging
    return render_403_for_employees unless current_repository.permit?(current_user, :read)
    update_config_id, public_key = params.require [:update_config_id, :public_key]
    # Even if the subsequent Twirp call fails for any reason, we should log the attempt for the Audit trail
    return render_403_for_employees unless current_repository_owns_update_config?(update_config_id)
    instrument_debug_credential_access
    payload = Dependabot::Twirp.debug_client.get_encrypted_config_payload(
      update_config_id: update_config_id.to_i,
      public_key: public_key,
    )
    flash[:debug_payload] = payload.encrypted_config_payload
    redirect_to :back
  rescue Dependabot::Twirp::ServiceUnavailableError
    render "stafftools/repository_dependabot/unavailable"
  rescue Dependabot::Twirp::Error => error
    render "stafftools/repository_dependabot/error", locals: { error: error }
  end

  private

  def ensure_dependabot_available
    render_404 unless GitHub.dependabot_enabled?
  end

  def list_update_configs
    Dependabot::Twirp.update_configs_client.list_update_configs(
      repository_id: current_repository.id,
      owner_id: current_repository.owner_id,
      config_file_exists: current_repository.dependabot_config_file_exists?,
    )
  end

  def current_repository_owns_update_config?(update_config_id)
    list_update_configs.update_configs.any? { |uc| uc.id == update_config_id.to_i }
  end

  def instrument_debug_credential_access
    instrument("staff.dependabot_debug_credentials_generated", instrumentation_payload)
  end

  def instrumentation_payload
    return { org: current_repository.owner, repository: current_repository } if current_repository.owner.is_a?(::Organization)

    { user: current_repository.owner, repository: current_repository }
  end

  def dependabot_secrets
    secrets_for_repository(
      current_repository,
      current_user,
      app: GitHub.dependabot_github_app,
      fetch_environments: false
    )
  end
end
