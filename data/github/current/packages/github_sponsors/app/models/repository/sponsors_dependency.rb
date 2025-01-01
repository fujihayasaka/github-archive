# typed: true
# frozen_string_literal: true

module Repository::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    belongs_to :owner_sponsors_listing_stafftools_metadata, primary_key: "sponsorable_id", foreign_key: "owner_id",
      inverse_of: :sponsorable_non_fork_public_repositories, class_name: "SponsorsListingStafftoolsMetadata"

    has_many :repository_sponsorables, dependent: :destroy, inverse_of: :repository
    has_many :sponsors_listing_featured_items, as: :featureable, dependent: :destroy
    has_many :sponsorship_repositories, dependent: :destroy, inverse_of: :repository
    has_many :sponsors_tiers

    # If this relation exists, that means the repository's owner has a public GitHub Sponsors profile and
    # can be sponsored.
    has_one :owner_repository_sponsorable, -> do
      T.bind(self, T.untyped)
      owner
    end, class_name: :RepositorySponsorable

    scope :with_sponsorable_owner, -> do
      joins(:repository_sponsorables).not_spammy.merge(RepositorySponsorable.owner)
    end

    # Any repository who has an associated user or organization who can be sponsored. Could be the repository's
    # owner or someone specified in a funding.yml file for the repository.
    scope :sponsorable, -> { joins(:repository_sponsorables).not_spammy.distinct }

    # Repositories that have the specified sponsorable users or orgs associated with them, either because the
    # sponsorables own the repository or are listed in a funding.yml file for the repository.
    scope :represented_by_sponsorable, ->(sponsorable_ids) do
      joins(:repository_sponsorables).merge(RepositorySponsorable.for_sponsorable(sponsorable_ids)).distinct
    end

    batch_method :show_sponsor_button? do |repos|
      next Hash.new(false) unless GitHub.sponsors_enabled?

      promises = repos.map do |repo|
        next Promise.resolve(false) if repo.global_health_files_repository?

        repo.async_batch_has_any_trade_restrictions?.then do |has_any_trade_restrictions|
          next false if has_any_trade_restrictions

          repo.async_has_funding_file?.then do |has_funding_file|
            next false unless has_funding_file

            repo.async_batch_funding_links_stafftools_disabled?.then do |funding_links_stafftools_disabled|
              next false if funding_links_stafftools_disabled

              repo.async_batch_repository_funding_links_enabled?
            end
          end
        end
      end

      results = Promise.all(promises).sync
      repos.zip(results).to_h
    end

    batch_method :sponsorable_owner? do |repos|
      next Hash.new(false) unless GitHub.sponsors_enabled?
      repo_ids_with_sponsorable_owners = RepositorySponsorable.owner.for_repository(repos)
        .pluck(:repository_id).to_set
      repos.map { |repo| [repo, repo_ids_with_sponsorable_owners.include?(repo.id)] }.to_h
    end

    batch_method :owner_sponsored_by_viewer? do |repos, viewer|
      next Hash.new(false) unless viewer
      results = Promise.all(repos.map { |repo| repo.async_owner_sponsored_by_viewer?(viewer) }).sync
      repos.zip(results).to_h
    end
  end

  # Public: Get the sponsorship from the specified user to the owner of this repository.
  #
  # sponsor_id - User or Organization ID, such as the ID of an author of a comment in one of this repository's issues
  # viewer - currently authenticated user, to determine whether the sponsor's identity is visible
  sig { params(sponsor_id: Integer, viewer: T.nilable(User)).returns(Promise[T.nilable(Sponsorship)]) }
  def async_owner_sponsorship_from(sponsor_id, viewer:)
    return Promise.resolve(T.let(nil, T.nilable(Sponsorship))) unless GitHub.sponsors_enabled?

    async_owner.then do |owner|
      Platform::Loaders::SponsorshipByCommentAuthorId.load(viewer, owner, sponsor_id)
    end
  end

  sig { params(viewer: User).returns(Promise[T::Boolean]) }
  def async_owner_sponsored_by_viewer?(viewer)
    async_owner.then do |the_owner|
      next false unless the_owner
      the_owner.async_sponsored_by_viewer?(viewer)
    end
  end

  sig { void }
  def unfeature_from_sponsors_profile
    sponsors_listing_featured_items.destroy_all
  end

  sig { params(actor: User, funding_change_type: T.any(String, Symbol)).void }
  def instrument_repo_funding_links_file_action(actor:, funding_change_type:)
    # Audit log
    instrument :repo_funding_links_file_action,
      actor: actor,
      prefix: :sponsors

    # Hydro
    GlobalInstrumenter.instrument("sponsors.repo_funding_links_file_action",
      repository: self,
      owner: owner,
      actor: actor,
      change_type: funding_change_type,
      platforms: funding_links_to_hydro
    )
  end

  sig { void }
  def update_sponsors_listing_metadata_if_necessary
    return unless GitHub.sponsors_enabled?

    owner_metadata = owner_sponsors_listing_stafftools_metadata
    return unless owner_metadata&.has_public_non_fork_repository?
    return if owner&.first_non_fork_public_repository.present?

    owner_metadata.update_column(:has_public_non_fork_repository, false)
  end

  sig { void }
  def enqueue_repo_sponsorables_job_for_sponsorable_owner
    # Check #sponsorable? on owner rather than using #sponsorable_owner? since #sponsorable_owner? relies on
    # a RepositorySponsorable record existing, which is what this job will create:
    if owner&.sponsorable?
      UpdateOwnerRepositorySponsorablesJob.perform_later(sponsorable_id: owner_id)
    end

    # Only care about if this repo inherits its funding.yml from the owner's .github repo at this point (right after
    # repo creation), because if a funding.yml is added to this new repo directly, RepositoryCheckPreferredFilesJob
    # will happen on push and we'll enqueue UpdateRepositorySponsorablesForRepositoryJob then:
    if global_health_files_repo && global_health_files_repo.preferred_files.exists?(:funding)
      UpdateRepositorySponsorablesForRepositoryJob.perform_later(repository_id: id)
    end
  end

  sig { void }
  def alert_sponsors_listing_has_public_non_fork_repository
    return unless public? && !fork?

    owner_metadata = owner_sponsors_listing_stafftools_metadata
    return unless owner_metadata

    return if owner_metadata.has_public_non_fork_repository?
    owner_metadata.update_column(:has_public_non_fork_repository, true)
  end
end
