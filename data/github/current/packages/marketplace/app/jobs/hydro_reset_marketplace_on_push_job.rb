# typed: true
# frozen_string_literal: true

class HydroResetMarketplaceOnPushJob < Repositories::PushHydroMessageJob
  include Marketplace::Domain::Provider

  use_primaries ApplicationRecord::Mysql5  # reset_docker_file_status writes to KV

  queue_as :hydro_reset_marketplace_on_push

  def perform
    return unless push_includes_default_branch?

    # Reset the repository's mobile and Dockerfile status if they exist, as pushing
    # code updates may change that status.
    #
    # The Dockerfile and movile statuses will only be used if the repo doesn't already
    # have CI, does not bother to run if CI is already running.
    if marketplace_domain.repository_settings.has_ci?(repository)
      marketplace_domain.repository_settings.clear_mobile_status(repository_id)
      marketplace_domain.repository_settings.clear_docker_file_status(repository_id)
    else
      marketplace_domain.repository_settings.set_mobile_status(repository)
      marketplace_domain.repository_settings.set_docker_file_status(repository)
    end
  end
end
