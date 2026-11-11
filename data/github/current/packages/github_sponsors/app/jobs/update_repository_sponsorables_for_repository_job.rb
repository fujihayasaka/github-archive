# typed: true
# frozen_string_literal: true

class UpdateRepositorySponsorablesForRepositoryJob < ApplicationJob
  queue_as :update_repository_sponsorables
  retry_on_dirty_exit

  def perform(repository_id:)
    return unless repository_id
    return unless GitHub.sponsors_enabled?

    repository = Repositories::Public.find_active(repository_id)
    return unless repository

    if funding_links_enabled?(repository)
      # Check for a funding.yml in the repository itself:
      update_or_destroy_repo_sponsorables_based_on_repo_funding_file(repository)

      # Check for a funding.yml in a .github repository owned by this repository's owner:
      update_or_destroy_repo_sponsorables_based_on_global_funding_file(repository)
    else
      with_write do
        repository.repository_sponsorables.with_source([:repo_funding_file, :global_funding_file]).destroy_all
      end
    end
  end

  private

  def funding_links_enabled?(repository)
    repository.repository_funding_links_enabled?
  end

  def update_or_destroy_repo_sponsorables_based_on_repo_funding_file(repository)
    if funding_file_exists?(repository, global: false)
      update_repo_sponsorables_for_source(repository, source: :repo_funding_file)
    else
      with_write do
        repository.repository_sponsorables.repo_funding_file.destroy_all
      end
    end
  end

  def update_or_destroy_repo_sponsorables_based_on_global_funding_file(repository)
    if funding_file_exists?(repository, global: true)
      update_repo_sponsorables_for_source(repository, source: :global_funding_file)
    else
      with_write do
        repository.repository_sponsorables.global_funding_file.destroy_all
      end
    end
  end

  def funding_file_exists?(repository, global:)
    repository.preferred_files.exists?(:funding, global: global)
  end

  def update_repo_sponsorables_for_source(repository, source:)
    sponsorable_ids = repository.funding_links.sponsorable_ids.to_set

    # Remove any repo-sponsorables that may exist for sponsorables no longer in the funding file:
    with_write do
      repository.repository_sponsorables.with_source(source).not_for_sponsorable(sponsorable_ids).destroy_all
    end

    # Ensure a repo-sponsorable exists for each sponsorable in the funding file:
    existing_sponsorable_ids = repository.repository_sponsorables.with_source(source).pluck(:sponsorable_id).to_set
    sponsorable_ids_to_add = sponsorable_ids - existing_sponsorable_ids
    sponsorable_ids_to_add.each do |sponsorable_id|
      with_write do
        repository.repository_sponsorables.create(source: source, sponsorable_id: sponsorable_id)
      end
    end
  end
end
