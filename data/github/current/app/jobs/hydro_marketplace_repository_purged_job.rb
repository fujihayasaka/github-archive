# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroMarketplaceRepositoryPurgedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_marketplace_repository_purged

  def perform
    mobile_key = Marketplace.domain.repository_settings.mobile_key(repository_id)
    docker_file_key = Marketplace.domain.repository_settings.docker_file_key(repository_id)

    has_mobile_key = Marketplace::KV.store.exists(mobile_key).value { true }
    has_docker_file_key = Marketplace::KV.store.exists(docker_file_key).value { true }

    ActiveRecord::Base.connected_to(role: :writing) do
      Marketplace::KV.store.del(mobile_key) if has_mobile_key
      Marketplace::KV.store.del(docker_file_key) if has_docker_file_key
    end
  end
end
