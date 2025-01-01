# typed: true
# frozen_string_literal: true

class HydroMarketplaceRepositoryPurgedJob < Repositories::RepositoryHydroMessageJob
  include Marketplace::Domain::Provider

  queue_as :hydro_marketplace_repository_purged

  def perform
    mobile_key = marketplace_domain.repository_settings.mobile_key(repository_id)
    docker_file_key = marketplace_domain.repository_settings.docker_file_key(repository_id)

    has_mobile_key = GitHub.kv.exists(mobile_key).value { true } # rubocop:todo GitHub/DoNotUseGlobalKv
    has_docker_file_key = GitHub.kv.exists(docker_file_key).value { true } # rubocop:todo GitHub/DoNotUseGlobalKv

    ActiveRecord::Base.connected_to(role: :writing) do
      GitHub.kv.del(mobile_key) if has_mobile_key # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.del(docker_file_key) if has_docker_file_key # rubocop:todo GitHub/DoNotUseGlobalKv
    end
  end
end
