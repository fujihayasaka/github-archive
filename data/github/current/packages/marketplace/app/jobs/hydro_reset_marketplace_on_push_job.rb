# typed: true
# frozen_string_literal: true

class HydroResetMarketplaceOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_reset_marketplace_on_push

  def perform
    return unless push_includes_default_branch?

    # Reset the repository's mobile and Dockerfile status if they exist, as pushing
    # code updates may change that status.
    #
    # The Dockerfile and mobile statuses will only be used if the repo doesn't already
    # have CI, does not bother to run if CI is already running.
    if Marketplace.domain.repository_settings.has_ci?(repository)
      Marketplace.domain.repository_settings.clear_mobile_status(repository_id)
      Marketplace.domain.repository_settings.clear_docker_file_status(repository_id)
    else
      Marketplace.domain.repository_settings.set_mobile_status(repository)
      Marketplace.domain.repository_settings.set_docker_file_status(repository)
    end
  end
end
