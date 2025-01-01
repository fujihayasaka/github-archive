# typed: true
# frozen_string_literal: true

class IntegrationInstallationUserAssociatedRepositoriesCacheJob < BatchedJob
  queue_as :integration_installation_user_associated_repositories_cache

  around_enqueue do |_job, block|
    block.call unless GitHub.enterprise?
  end

  discard_on ActiveJob::DeserializationError
  retry_on_dirty_exit

  def next_batch(installation, offset_item_id:, **options)
    return [] unless installation.target.organization?

    installation.target.members.
      order("id ASC").
      where("id > ?", offset_item_id).
      limit(BATCH_SIZE)
  end

  def process_batch(members, installation, **options)
    members.each do |member|
      IntegrationInstallation::UserAssociatedRepositories.invalidate_cache(
        installation: installation,
        user: member
      )
    end
  end
end
