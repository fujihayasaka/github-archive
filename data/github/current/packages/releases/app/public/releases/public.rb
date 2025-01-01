# typed: strict
# frozen_string_literal: true

module Releases
  module Public
    PER_PAGE = ::Release::PER_PAGE
    BODY_CHAR_LIMIT = ::Release::BODY_CHAR_LIMIT
    LIST_VIEW_BODY_CHAR_LIMIT = 10_000

    # Public: The latest published full Release for the given repository.
    sig { params(repo: ::Repository, user: T.nilable(::User)).returns(T.nilable(IRelease)) }
    def self.latest_for_repository(repo, user)
      repo.latest_release(user)
    end

    # Public: The number of published releases for the given repository.
    sig { params(repository_id: Integer).returns(Integer) }
    def self.published_release_count_for_repository(repository_id)
      Release.published.where(repository_id: repository_id).count
    end

    # Public: Fetch the release public models for the given ids.
    #
    # Options:
    # - relationships - Option to pass to includes
    #
    # Returns an array of Releases
    sig do
      params(
        release_ids: T::Array[Integer],
        relationships: T.nilable(T::Hash[Symbol, T.untyped]), # TODO: better type
      ).returns(T::Array[IRelease])
    end
    def self.load_releases(release_ids, relationships: nil)
      query = Release.where(id: release_ids)

      if relationships
        query = query.includes(relationships)
      end

      query.to_a
    end

    # Public: Fetch the release public models with the repository loaded for the given ids.
    #
    # Options:
    # - repository - The repository to fetch the releases for.
    #
    # Returns an array of Releases
    sig do
      params(
        release_ids: T::Array[Integer],
        repository: ::Repository,
      ).returns(T::Array[IRelease])
    end
    def self.load_releases_for_repository(release_ids, repository)
      repository.releases.where(id: release_ids).to_a
    end

    # Public: Fetch the release public models for the given ids and prefill the tag property of the releases from gitrpc.
    #
    # Options:
    # - repository - The repository to fetch the releases for.
    #
    # Returns an array of Releases
    sig { params(release_ids: T::Array[Integer], repository: ::Repository).returns(T::Array[IRelease]) }
    def self.load_releases_and_prefill_tags(release_ids, repository)
      releases = load_releases_for_repository(release_ids, repository)

      Release.prefill_tags(releases, repository)

      releases
    end

    # Public: Fetch the release public model for the given id
    sig { params(release_id: Integer).returns(T.nilable(IRelease)) }
    def self.load_release(release_id)
      load_releases([release_id]).first
    end

    # Public: Fetch the asset release model for the given id
    sig { params(release_asset_id: Integer).returns(T.nilable(IReleaseAsset)) }
    def self.load_asset(release_asset_id)
      load_assets([release_asset_id]).first
    end

    # Public: Fetch the asset release model for the given ids
    sig { params(release_asset_ids: T::Array[Integer]).returns(T::Array[IReleaseAsset]) }
    def self.load_assets(release_asset_ids)
      ::ReleaseAsset.where(id: release_asset_ids).to_a
    end

    # Public: Find the release for the given tag.
    #
    # TODO: remove the `include_drafts` argument. This should be an internal
    # authorization check and the responsibility of the service, not the caller.
    sig { params(repo_id: Integer, tag: String, include_drafts: T::Boolean).returns(T.nilable(IRelease)) }
    def self.load_by_tag(repo_id, tag, include_drafts: false)
      releases = ::Release.for_repo(repo_id, include_drafts: include_drafts)
      releases.find_by(tag_name: tag)
    end

    # Public: Find the release for the given pending tag.
    sig { params(repo_id: Integer, tag: String).returns(T.nilable(IRelease)) }
    def self.load_by_pending_tag(repo_id, tag)
      releases = ::Release.for_repo(repo_id, include_drafts: true)
      releases.find_by(pending_tag: tag)
    end

    # Gets all the releases authored by the given user across repos.
    sig { params(user_id: Integer).returns(T::Array[IRelease]) }
    def self.load_by_author(user_id)
      release_ids = ActiveRecord::Base.connected_to(role: :reading) do
        ::Release.where(author_id: user_id).to_a
      end
    end

    # Public: Build release from tag
    sig { params(repository: Repository, tag: String).returns(T.nilable(IRelease)) }
    def self.build_from_tag(repository, tag)
      ::Release.build_tag_ref(repository, tag)
    end

    # Public: Creates a new release for the repository.
    # attributes - a Hash of the attributes to be assigned to the release. Supported keys:
    #              repository_id (Integer, required)
    #              author_id (Integer, required)
    #              tag_name (String, required)
    #              name (String)
    #              body (String)
    #              draft (Boolean)
    #              prerelease (Boolean)
    #              target_commitish (String)
    #              generate_release_notes (Boolean) - whether to generate release notes name and body for
    #                 the release. Will not overwrite the provided name. Appends
    #                 generated body content to the provided body.
    #              make_latest (Boolean) - whether to set this release as the latest release for the repository.
    # Returns Release model
    sig { params(attributes: ICreateReleaseAttributes).returns(IRelease) }
    def self.create_release(attributes)
      attributes = attributes.slice(:repository_id, :author_id, :tag_name, :name, :body, :draft, :prerelease, :target_commitish, :generate_release_notes, :make_latest)

      # When the :attested_releases feature flag is removed, this can go back inside the generate_release_notes
      # condition
      repository = Repositories::Public.find_active!(attributes[:repository_id])

      if attributes.delete(:generate_release_notes)
        name, body = generate_release_notes(
          repository,
          attributes[:tag_name],
          target_commitish: attributes[:target_commitish]
        )

        # Do not overwrite the name if it was provided to the API
        attributes[:name] = attributes[:name] || name
        # Prepend the provided body to the generated one if provided to the API
        body = attributes[:body] + "\n\n" + body if attributes[:body].present?
        attributes[:body] = body
      end

      ::Release.create(attributes).tap do |release|
        if release.errors.empty? && release.published? &&
            repository.feature_enabled_for_repo_or_owner?(:attested_releases)

          # Attest after create so we have release_id available for attestation
          release.attestation_id = ReleaseAttestationManager.attest_release(release)

          # Save again to persist attestation_id
          release.save(validate: false)
        end
      end
    end

    # Public: Persists a release record and (potentially) attests it.
    #
    # Returns true if the release was saved, false otherwise.
    sig { params(release: Release).returns(T::Boolean) }
    def self.save_release(release)
      repository = T.must(release.repository)

      # Attestation is only for published releases which don't already have an
      # attestation. Currently, only for repos with the attested_releases
      # feature flag enabled.
      if repository.feature_enabled_for_repo_or_owner?(:attested_releases) &&
          release.published? && release.attestation_id.nil?

        # If release has not been persisted we must do so before we can attest
        # it. This ensures the release_id is available for attestation.
        if release.new_record?
          valid = T.let(release.save, T::Boolean)
        else
          valid = T.let(release.valid?, T::Boolean)
        end

        # Exit early w/o attestation if release is not valid
        return false unless valid

        # Capture the attestation_id for the release and re-save.
        begin
          release.attestation_id = ReleaseAttestationManager.attest_release(release)
          release.save(validate: false)
        rescue Releases::Error
          release.errors.add(:base, "failed to attest")
          false
        end
      else
        release.save
      end
    end

    # Public: Retrieve a page of releases for a repository
    #
    # Returns an Array of Release objects for the given page, convert the
    # repository tags to Release objects
    sig { params(repository: Repository, after: T.nilable(String)).returns(T::Array[IRelease]) }
    def self.tags_as_releases(repository, after: nil)
      ::Release.page_tags(repository, after: after)
    end

    # Public: Retrieve a page of releases that match the given query
    #
    # Returns a Search Results object that contains the items and details for the given page.
    sig do
      params(
        repository: Repository,
        current_user: T.nilable(User),
        page: Integer,
        limit: Integer,
        filter_phrase: T.nilable(String),
        allow_drafts: T::Boolean
      ).returns(::Search::Results[IRelease])
    end
    def self.query_releases(repository, current_user, page: 1, limit: PER_PAGE, filter_phrase: nil, allow_drafts: false)
      ::Release.query_releases(repository, current_user, page: page, limit: limit, filter_phrase: filter_phrase, allow_drafts: allow_drafts)
    end

    # Public: Find published, non-prereleases for the repository
    sig { params(repository_id: Integer).returns(T::Boolean) }
    def self.published_releases_for_repository?(repository_id)
      Release.where(repository_id: repository_id, prerelease: false, state: "published").exists?
    end

    # Public: Generate Release Notes for a given tag and target_commitish
    #
    # Returns a trio of strings - title, body, warning_message - for the title and description of
    # the release and any warning message that may have accured during the generation process
    sig do
      params(
        repository: ::Repository,
        tag_name: String,
        target_commitish: T.nilable(String),
        previous_tag_name: T.nilable(String),
        configuration_file_path: T.nilable(String),
      ).returns(IReleaseNotes)
    end
    def self.generate_release_notes(repository, tag_name, target_commitish: nil, previous_tag_name: nil, configuration_file_path: nil)
      target_commitish ||= repository.default_branch

      raise Releases::Error, "Invalid target_commitish parameter" if repository.commit_for_ref(target_commitish).blank?

      release = Helper.load_or_build_by_tag(repository, tag_name, include_drafts: true)

      # If no release exists for the given tag, new up a draft release with the
      # necessary properties for generating release notes
      if release.nil?
        release = Release.new repository: repository, pending_tag: tag_name, target_commitish: target_commitish, state: :draft
      end

      T.cast(release, Release).generate_release_notes(previous_tag_name: previous_tag_name, configuration_file_path: configuration_file_path)
    end

    # Public: Return the subset of a collection of Releases that have tags deletable by the given user.
    sig { params(user: T.nilable(::User), releases: T::Array[IRelease]).returns(T::Array[IRelease]) }
    def self.protected_tags_deletable_by?(user, releases)
      ::Release.protected_tags_deletable_by?(user, releases)
    end

    # Public: The set of reactable emotions for a release.
    sig { returns(T::Array[String]) }
    def self.emotions
      ::Release.emotions
    end

    # Public: The object which implements the expected storage methods for handling
    #   release asset content.
    #
    # TODO: currently this is just the active record class for ReleaseAsset. In the
    #   long term, we'd expect to have a formal interface implemented by a public
    #   object, but this is where we start.
    sig { returns(T.class_of(ReleaseAsset)) }
    def self.storage_interface
      ::ReleaseAsset
    end

    # Stafftools: Unpublish the releases which are not searchable.
    #
    # When a tag is being deleted, a corresponding release normally should be unpublished by HydroReleasesOnPushJob.
    # See https://github.com/github/repos/issues/5473#issuecomment-1759493731.
    # However, due to arbitrary validation failures/bugs, changes for such Releases sometimes are not saved into the database.
    # Thus, leaving Releases in a published but not searchable state.
    # That ends up contributing to the releases counter for the customers, but they're not able to see such releases.
    # See for example https://github.com/github/repos/issues/7507.
    # In such cases, we want to manually unpublish non searchable releases for them via Stafftools or Rails console.
    #
    # Returns an object containing counts of all iterated releases, how many of them are searchable and how many are not.
    # As well as an array of IDs in case of some releases being unpublished.
    sig { params(repo_id: Integer, verbose: T::Boolean, dry_run: T::Boolean, perform_validations: T::Boolean).returns(T::Hash[T.untyped, T.untyped]) }
    def self.unpublish_unsearchable_releases(repo_id:, verbose: false, dry_run: true, perform_validations: true)
      searchable = []
      unsearchable = []
      unpublished_ids = []

      Release.where(repository_id: repo_id).includes(:repository).find_each do |x|
        if !x.is_searchable?
          unsearchable << x
          pp "Unsearchable release: ID=#{x.id} name=#{x.name}" if verbose

          if !dry_run
            x.state = :draft

            if perform_validations == true
              # Throw validation errors, so we can probably check them in Sentry or Rails console.
              x.save!
            else
              x.save(validate: false)
            end

            unpublished_ids << x.id
            pp "Unpublish release: ID=#{x.id}" if verbose
          end
        else
          searchable << x
        end
      end

      {
        all: (searchable + unsearchable).count,
        searchable: searchable.count,
        unsearchable: unsearchable.count,
        unpublished_ids: unpublished_ids
      }
    end
  end
end
