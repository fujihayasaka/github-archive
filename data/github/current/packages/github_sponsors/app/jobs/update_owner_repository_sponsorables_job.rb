# typed: true
# frozen_string_literal: true

# Public: Background job to create source=owner RepositorySponsorable records as necessary as well as delete all
# RepositorySponsorable records for a particular user/org when they are no longer sponsorable.
class UpdateOwnerRepositorySponsorablesJob < ApplicationJob
  queue_as :update_repository_sponsorables
  retry_on_dirty_exit

  class RepositorySponsorableCreationError < StandardError; end

  # sponsorable_id - Integer ID for a User or Organization
  def perform(sponsorable_id: nil)
    return if sponsorable_id.nil?
    return unless GitHub.sponsors_enabled?

    sponsorable = User.find_by(id: sponsorable_id)
    return unless sponsorable

    if sponsorable.sponsorable?
      remove_outdated_repo_sponsorables_for_owner(sponsorable)
      ensure_repo_sponsorable_exists_for_each_owned_repo(sponsorable)
    else
      # Source doesn't matter: if the sponsorable can no longer be sponsored, want to remove them entirely from
      # the table:
      with_write { sponsorable.repository_sponsorables.destroy_all }
    end
  end

  private

  def remove_outdated_repo_sponsorables_for_owner(sponsorable)
    with_write do
      sponsorable.repository_sponsorables.owner.not_for_repository(sponsorable.repositories.select(:id)).destroy_all
    end
  end

  def ensure_repo_sponsorable_exists_for_each_owned_repo(sponsorable)
    existing_repo_sponsorables_for_source = sponsorable.repository_sponsorables.owner
    repo_ids_to_add = sponsorable.repositories
      .where.not(id: existing_repo_sponsorables_for_source.select(:repository_id))
      .pluck(:id)

    repo_ids_to_add.each do |repo_id|
      repo_sponsorable = sponsorable.repository_sponsorables.new(repository_id: repo_id, source: :owner)

      # Can skip the per-record validation because we already know the sponsorable can indeed be sponsored:
      repo_sponsorable.skip_sponsorable_can_be_sponsored_check = true

      # Don't need the per-record uniqueness validation, which would run a query, because we already filtered out
      # existing repo-sponsorables:
      repo_sponsorable.skip_uniqueness_check = true

      with_write do
        RepositorySponsorable.throttle do
          repo_sponsorable.save!
        end
      end
    end
  end
end
