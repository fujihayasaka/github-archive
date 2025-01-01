# typed: false
# frozen_string_literal: true

module Packages
  module Migration
    class MigratePackageJob < Packages::Migration::MigrationJob
      default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

      class PackageNotFoundError < RuntimeError; end
      class UnsupportedPackageTypeError < RuntimeError; end
      class MissingDataError < RuntimeError; end
      class MigrationNotSupported < RuntimeError; end

      BATCH_SIZE = 50

      queue_as :packages_migration_migrate_package

      retry_on_dirty_exit

      # wait time is randomly selected between 30 seconds and 5 minutes
      retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

      discard_on PackageNotFoundError
      discard_on UnsupportedPackageTypeError
      discard_on MigrationNotSupported

      attr_reader :package

      def perform(*args, force: false, retry_failed: false, is_error_retry: false, last_migrated_package_id: 0, initial_start: Time.now.utc, offset_item_id: 0, progress: 0, **options)
        if GitHub.enterprise?
          # To control DB concurrency, acquire lock on the job
          # Ensure only one concurrent job is running
          lock_key = "migrate-package-job-restraint"
          concurrent_jobs = 1
          lock_ttl = 5.minutes

          log(msg: "Try acquiring lock at: #{Time.now.utc}")
          restraint = GitHub::Restraint.new
          restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
            log(msg: "Lock acquired at #{Time.now.utc}. Starting package migration job")
            super
          end
        else
          super
        end
      end

      def next_batch(pkg_id, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
        init_package(pkg_id)

        log(msg: "retrieving versions for package with id #{pkg_id}, name #{package_name}, org_name #{package_namespace}")

        ActiveRecord::Base.connected_to(role: :reading) do
          get_package_versions(package_type, unmigrated_only: !is_forced, failed_only: is_failed_retry, is_error_retry: is_error_retry, index: "index_package_versions_on_package_id_deleted_at_and_such")
          .where("id > ?", offset_item_id)
          .order(:id)
          .limit(BATCH_SIZE)
        end
      end

      def process_batch(batch, pkg_id, **options)

        if batch.count == 0
          return log(msg: "no unmigrated versions found for package with id #{pkg_id}")
        end

        batch.each do |version|
          if !GitHub.enterprise? && package_type == "docker" && should_skip?
            log(msg: "skipping package #{package_name}")
            save_migration_state(version: version, migration_state: "unmigrated")
            next
          end

          begin
            msg = serialize_msg(version)
            if does_package_name_conflict?
              log(msg: "package name #{package_name} conflicts with existing v2 package")
              save_migration_state(version: version, migration_state: "retriable_error")
              update_migration_status_when_error
            else
              save_migration_state(version: version, migration_state: "pending")
              log(msg: "emitting version migration initiated event for version with id #{version.id}")
              GlobalInstrumenter.instrument("package_registry.package_version_migration_initiated", msg)
            end

          rescue MissingDataError => e
            log(msg: "version with id #{version.id} is unmigratable and failed with error : #{e.message}")
            save_migration_state(version: version, migration_state: "error")
            update_migration_status_when_error
          end

        end

        log(msg: "Batch processing finished at #{Time.now.utc}")
      end

      private

      def init_package(id)

        if id.nil? || id == 0
          log(msg: (msg = "invalid package id given"))
          raise PackageNotFoundError.new(msg)
        end

        @package = Registry::Package.find_by(id: id)

        if @package.nil?
          log(msg: (msg = "package with id #{id} not found"))
          raise PackageNotFoundError.new(msg)
        end

        # enterprise only support docker migration
        unless (!GitHub.enterprise? && package_type.in?(%w[docker npm rubygems nuget])) || (GitHub.enterprise? && package_type == "docker")
          log(msg: (msg = "package type #{package.package_type} is not supported"))
          raise UnsupportedPackageTypeError.new(msg)
        end
      end

      def save_migration_state(version:, migration_state:)
        is_already_completed = version.migration_state == "complete"
        is_going_pending = migration_state == "pending"
        size_in_bytes = ActiveRecord::Base.connected_to(role: :reading) { version.files.pluck(:size).sum }
        pkg_visibility = package.visibility

        version.migration_state = migration_state

        ::Registry::PackageVersion.throttle_writes_with_retry(max_retry_count: 5) do
          ::Billing::SharedStorage::ArtifactEvent.throttle_with_retry do
            ::Registry::PackageVersion.transaction do
              ::Billing::SharedStorage::ArtifactEvent.transaction do
                version.save!(touch: false)

                # Inversion of events added in `version-migration-status-processor`
                if is_already_completed && is_going_pending && !version.deleted? && package_type != "docker"
                  events = [
                    {
                      owner_id: package.owner.id,
                      repository_id: package.repository_id,
                      effective_at: Time.current,
                      source: :gpr,
                      repository_visibility: pkg_visibility,
                      event_type: :add,
                      size_in_bytes: size_in_bytes,
                    },
                  ]

                  events << {
                    owner_id: package.owner.id,
                    repository_id: nil,
                    effective_at: Time.current,
                    source: :packages_v2,
                    repository_visibility: :private,
                    event_type: :remove,
                    size_in_bytes: size_in_bytes,
                  } if pkg_visibility != "public"

                  ::Billing::SharedStorage::ArtifactEvent.create!(events)
                end
              end
            end
          end
        end

        GitHub.dogstats.increment "migrate_package_job.state",
          tags: ["migration_state:#{migration_state}", "proto:#{package_type}", "namespace:#{package_namespace}"]
      end

      # Update the migration status in DB for enterprise
      def update_migration_status_when_error
        return if !(GitHub.enterprise? && package_type == "docker")

        # unmigrated + pending + retriable_error
        unmigrated_ver_for_namespace = Registry::PackageVersion.joins(:package)
          .where(
            package: {
              owner_id: package.owner.id,
              package_type: package_type
            }
          )
          .unmigrated

        # retriable_error
        failed_ver_for_namespace = Registry::PackageVersion.joins(:package)
          .where(
            package: {
              owner_id: package.owner.id,
              package_type: package_type
            }
          )
          .migratable(package_type, error_only: true)

        unmigrated_count = unmigrated_ver_for_namespace.where(registry_package_id: package.id).count
        failed_count = failed_ver_for_namespace.where(registry_package_id: package.id).count

        unmigrated_ver_count = unmigrated_ver_for_namespace.count
        failed_ver_count = failed_ver_for_namespace.count

        GitHub.logger.info(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.registry.package_id" => package.id,
          "gh.registry.package_type" => package_type,
          "gh.registry.owner_id" => package.owner.id,
          "gh.registry.unmigrated_count" => unmigrated_count,
          "gh.registry.failed_count" => failed_count,
          "gh.registry.unmigrated_ver_count" => unmigrated_ver_count,
          "gh.registry.failed_ver_count" => failed_ver_count,
        )

        migration_run = Registry::PackagesMigration.find_by_state(:inProgress)
        return if migration_run.nil?

        if unmigrated_count == 0    # all versions of a package are migrated
          migration_run.update(success_pkg_count: migration_run.success_pkg_count + 1)
        elsif unmigrated_count == failed_count    # some versions have failed when package migration has completed
          migration_run.update(failed_pkg_count: migration_run.failed_pkg_count + 1)
        end

        if unmigrated_ver_count == 0    # All versions of an org are successfully migrated
          migration_run.update(success_org_count: migration_run.success_org_count + 1)
        elsif unmigrated_ver_count == failed_ver_count    # some versions have failed when package migration has completed for an org
          migration_run.update(failed_org_count: migration_run.failed_org_count + 1)
        end

        migrated_pkg_count = migration_run.success_pkg_count + migration_run.failed_pkg_count

        GitHub.logger.info(
          "Updated migration run",
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.registry.migration_run_id" => migration_run.id,
          "gh.registry.success_pkg_count" => migration_run.success_pkg_count,
          "gh.registry.failed_pkg_count" => migration_run.failed_pkg_count,
          "gh.registry.success_org_count" => migration_run.success_org_count,
          "gh.registry.failed_org_count" => migration_run.failed_org_count,
          "gh.registry.migrated_pkg_count" => migrated_pkg_count,
        )

        if migration_run.total_pkg_count > migrated_pkg_count && migrated_pkg_count % 5 == 0
          channel = GitHub::WebSocket::Channels.packages_migration(migration_run.id)
          GitHub::WebSocket.notify_packages_migration_channel(migration_run, channel)
        end

        if migration_run.success_org_count + migration_run.failed_org_count == migration_run.total_org_count
          GitHub.logger.info(
            "Registry packages migration finished",
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.owner_id" => migration_run.owner.id,
            "gh.registry.total_org_count" => migration_run.total_org_count,
            "gh.registry.success_org_count" => migration_run.success_org_count,
            "gh.registry.failed_org_count" => migration_run.failed_org_count,
            "gh.registry.total_pkg_count" => migration_run.total_pkg_count,
            "gh.registry.success_pkg_count" => migration_run.success_pkg_count,
            "gh.registry.failed_pkg_count" => migration_run.failed_pkg_count,
          )

          migration_run.update(state: :completed)
          channel = GitHub::WebSocket::Channels.packages_migration("package_settings")
          GitHub::WebSocket.notify_packages_migration_channel(migration_run, channel)
        end
      end

      def package_namespace
        return @package_namespace if defined?(@package_namespace)
        @package_namespace = package&.owner&.login
      end

      def package_name
        @package_name ||= (package_type == "docker" ? "#{package&.repository&.name}/#{package&.name}" : "#{package&.name}")
      end

      def package_type
        return @package_type if defined?(@package_type)
        @package_type = package&.package_type
      end

      def rms_migrator_client
        @rms_migrator_client ||= PackageRegistry::Twirp.migrator_client
      end

      def should_skip?(repo: package&.repository)
        return @should_skip if defined?(@should_skip)
        @should_skip = GitHub.flipper[:packages_docker_v1_skip_migration].enabled?(repo)
      end

      def does_package_name_conflict?(namespace: package_namespace, name: package_name, ecosystem: package_type)
        return @does_package_name_conflict if defined?(@does_package_name_conflict)
        ecosystem = ecosystem == "docker" ? :CONTAINER : ecosystem
        @does_package_name_conflict = rms_migrator_client.does_name_conflict?(namespace: namespace, package_name: name, ecosystem: ecosystem)
      rescue PackageRegistry::Twirp::Error => e
        log(msg: "error occured while checking for package name conflict: #{e.message}")
        true
      end

      def get_package_versions(package_type, unmigrated_only: true, failed_only: false, is_error_retry: false, index: nil)
        if index.nil?
          query = package.package_versions.migratable(package_type, unmigrated_only: unmigrated_only, failed_only: failed_only, is_error_retry: is_error_retry)
        else
          query = package.package_versions.use_index(index).migratable(package_type, unmigrated_only: unmigrated_only, failed_only: failed_only, is_error_retry: is_error_retry)
        end

        # index=nil is used in fetching last_migrated_version_id
        # there we don't need to preload the files, tags etc.
        return query if package_type == "docker" || index.nil?
        query = query.includes(:files, :tags)
        if package_type == "rubygems"
          query = query.includes(:dependencies, :rubygem_summary, :rubygem_readme, package: :repository)
        elsif package_type == "nuget"
          query = query.includes(:metadata, package: :repository)
        end

        query
      end

      def validate_field(name:, value:)

        if value.nil?
          log(msg: (msg = "missing value for field #{name}"))
          raise MissingDataError.new msg
        end

        value
      end

      def get_file_guid(repo_id:, sha256:)

        # Packages and versions are de-duped in a repo. For example if an image named alpine is pushed to
        # repo test and then the same alpine image is re-tagged and pushed to repo test as busybox there
        # will only be records in the package_files table for the versions of the last pushed image busybox.
        # Because of this when querying the package_files table we need to query against all packages in the repo.
        # Querying against all packages in the repo also handles another edge case where if a version is re-tagged
        # the files get associated with the 'docker-base-layer' instead of the newly tagged version.
        guid = Registry::File.joins(package_version: :package)
          .where(
            package: {
              repository_id: repo_id
            }
          )
          .where(sha256: sha256.delete_prefix("sha256:"))
          .limit(1)
          .pluck(:guid)
          .first

        validate_field(name: "guid with #{sha256}", value: guid)
      end

      def last_migrated_version_id
        #It has been observed that the correct index is not being used with limit(1) and the query is getting timed out. Hence using the index.
        @last_migrated_version_id ||=
        ActiveRecord::Base.connected_to(role: :reading) do
          get_package_versions(package_type, index: "index_package_versions_on_package_id_deleted_at_and_such")
            .order(id: :desc)
            .limit(1)
            .pluck(:id)
            .first
        end
      end

      def serialize_msg(version)

        if package_type == "docker"
          aliases_value = version&.original_name.nil? ? version&.version : version&.original_name
        else
          aliases_value = version&.version
        end

        {
          package: serialize_package(version),
          version: serialize_version(version),
          owner_id: validate_field(name: "owner_id", value: version&.package&.owner_id),
          aliases: [validate_field(name: "aliases", value: aliases_value)],
          initiated_at: Time.now.utc,
          is_forced: is_forced,
          last_migrated_package_id: last_migrated_package_id,
          last_migrated_version_id: last_migrated_version_id
        }.tap do |msg|
          if package_type == "docker"
            msg[:blob_store_paths] = serialize_blob_store_paths_docker(serialized_package: msg[:package], serialized_version: msg[:version])
          else
            msg[:blob_store_paths] = serialize_blob_store_paths_for_eco(version)
            msg[:file] = serialize_package_file(version)
            msg[:aliases] = serialize_package_tags(version)
          end
        end
      end

      def serialize_package_file(version)
        package_file = version.files.first
        validate_field(name: "package file", value: package_file)

        serialized_package_file = {
          id: package_file.id,
          package_version_id: package_file.package_version_id,
          file_name: package_file.filename,
          sha1: package_file.sha1,
          md5: package_file.md5,
          uploader_id: package_file.uploader_id,
          guid: package_file.guid,
          size: package_file.size,
          state: package_file.state,
          created_at: package_file.created_at,
          updated_at: package_file.updated_at,
          sha256: package_file.sha256,
          sri_512: package_file.sri_512
        }
        serialized_package_file
      end

      def serialize_package_tags(version)
        version.tags.pluck(:name)
      end

      def serialize_package(version)

        p = version&.package

        package = {
          id: p&.id,
          namespace: p&.owner&.login,
          name: package_type == "docker" ? "#{p&.repository&.name}/#{p&.name}" : "#{p&.name}",
          ecosystem: package_type == "docker" ? :CONTAINER : package_type.upcase.to_sym,
          created_at: p&.created_at,
          updated_at: p&.updated_at,
          repo_id: p&.repository_id,
          visibility: p&.repository&.visibility&.upcase&.to_sym,
          author_id: version&.author_id,
          author_type: { user: :ACTOR_TYPE_USER, bot: :ACTOR_TYPE_INSTALLATION }.fetch(version&.author&.type&.downcase&.to_sym, :ACTOR_TYPE_UNSPECIFIED)
        }
        # Validate the required fields
        package.each { |key, val| validate_field(name: "package.#{key}", value: val) }

        # Change milliseconds to 0 for package's deleted_at field as the version's deleted_at time does not include milliseconds.
        # Copy the original name as <repo_name>/<package_name> for a deleted docker package
        # Refer issue https://github.com/github/c2c-package-registry/issues/5162 for more details.
        package.merge(
          deleted_at: !p&.deleted_at.nil? ? p&.deleted_at.change(usec: 0) : p&.deleted_at,
          original_name: (!p&.original_name.nil? && package_type == "docker") ? "#{p&.repository&.name}/#{p&.original_name}" : p&.original_name
        )
      end

      def serialize_version(version)
        v = {
          id: version&.id,
          name: package_type == "docker" ? "sha256:#{version&.sha256}" : version&.version,
          ecosystem: package_type == "docker" ? :CONTAINER : package_type.upcase.to_sym,
          created_at: version&.created_at,
          updated_at: version&.updated_at,
        }

        # Validate the required fields
        v.each { |key, val| validate_field(name: "version.#{key}", value: val) }

        if package_type == "docker"
          v[:container_metadata] = serialize_container_metadata(version)
        elsif package_type == "npm"
          v[:npm_metadata] = serialize_npm_metadata(version)
        elsif package_type == "rubygems"
          v[:rubygems_metadata] = serialize_rubygems_metadata(version)
        elsif package_type == "nuget"
          v[:nuget_metadata] = serialize_nuget_metadata(version)
        end

        v.merge(
          download_count: version&.downloads_total_count,
          deleted_at: version&.deleted_at,
          original_name: version&.original_name,
        )
      end

      def serialize_npm_metadata(version)
        validate_field(name: "manifest", value: version&.package_manifest)
        manifest = JSON.parse(version&.package_manifest).with_indifferent_access

        dist = {}
        if manifest.dig(:dist).present?
          dist = {
            shasum: manifest.dig(:dist, :shasum),
            tarball: manifest.dig(:dist, :tarball),
            integrity: manifest.dig(:dist, :integrity)
          }
        end

        author_from_metadata = {}
        if manifest.dig(:author).present?
          if manifest.dig(:author).is_a?(String)
            author_from_metadata = {
              name: manifest.dig(:author)
            }
          else
            author_from_metadata = {
              email: manifest.dig(:author, :email),
              name: manifest.dig(:author, :name),
              url: manifest.dig(:author, :url)
            }
          end
        end

        repository_from_metadata = {}
        if manifest.dig(:repository).present?
          if manifest.dig(:repository).is_a?(String)
            repository_from_metadata = {
              type: "git",
              url: manifest.dig(:repository)
            }
          else
            repository_from_metadata = {
              type: manifest.dig(:repository, :type).to_s,
              url: manifest.dig(:repository, :url),
              directory: manifest.dig(:repository, :directory)
            }
          end
        end

        bugs_from_metadata = {}
        if manifest.dig(:bugs).present?
          if manifest.dig(:bugs).is_a?(String)
            bugs_from_metadata = {
              url: manifest.dig(:bugs)
            }
          else
            bugs_from_metadata = {
              url: manifest.dig(:bugs, :url),
            }
          end
        end


        bin_from_metadata = {}
        if manifest.dig(:bin).present?
          if manifest.dig(:bin).is_a?(String)
            bin_from_metadata[version&.package&.name.to_s] = manifest.dig(:bin)
          else
            bin_from_metadata = manifest.dig(:bin)
          end
        end

        npm_metadata = {
          name: manifest.dig(:name),
          version: manifest.dig(:version),
          npm_user: "",
          author: author_from_metadata,
          published_via_actions: version&.published_via_actions,
          deleted_by_id: version&.deleted_by_id,
          npm_version: manifest.dig(:_npmVersion),
          node_version: manifest.dig(:_nodeVersion),
          id: manifest.dig(:_id),
          release_id: version&.release_id,
          commit_oid: version&.commit_oid,
          bugs: bugs_from_metadata,
          dependencies: manifest.dig(:dependencies),
          dev_dependencies: manifest.dig(:devDependencies),
          optional_dependencies: manifest.dig(:optionalDependencies),
          peer_dependencies: manifest.dig(:peerDependencies),
          dist: dist,
          git_head: manifest.dig(:gitHead),
          homepage: manifest.dig(:homepage),
          license: manifest.dig(:license),
          main: manifest.dig(:main),
          repository: repository_from_metadata,
          readme: manifest.dig(:readme),
          scripts: manifest.dig(:scripts),
          description: manifest.dig(:description),
          maintainers: manifest.dig(:maintainers),
          contributors: manifest.dig(:contributors),
          engines: manifest.dig(:engines),
          keywords: manifest.dig(:keywords),
          files: manifest.dig(:files),
          bin: bin_from_metadata,
          man: manifest.dig(:man),
          os: manifest.dig(:os),
          cpu: manifest.dig(:cpu),
          directories: manifest.dig(:directories),
        }
        npm_metadata
      end

      def serialize_rubygems_metadata(version)
        return {} unless version

        # generate metadata as per v2
        # https://github.com/github/registry/blob/be9c680ac4fea44102afdadb05632aa725492ac2/clients/package_creator_v2.go#L337
        {
          name: version.package.name,
          # summary comes from version -> metadata -> summary
          description: version.rubygem_summary&.value.present? ? version.rubygem_summary&.value.to_s.force_encoding("UTF-8") : version.rubygem_summary&.value,
          # readme comes from version -> metadata -> readme
          readme: version.rubygem_readme&.value.present? ? version.rubygem_readme&.value.to_s.force_encoding("UTF-8") : version.rubygem_readme&.value,
          version_info: { version: version.version },
          repo: version.package.repository.http_url,
          dependencies: version.dependencies.map do |d|
            d.slice(:name, :version, :dependency_type).symbolize_keys
          end,
          # we keep it empty/default for new v2 packages, will do the same here as well
          # platform: "",
          # we don't have this data in v1
          # homepage: "",
          # we don't have this data in v1
          # metadata: {},
          # doesn't apply for rubygems
          # commit_oid: "",
        }
      end

      def serialize_nuget_metadata(version)
        metadata = version&.metadata.pluck(:name, :value).to_h
        nuget_metadata_repository = {}
        if !version.package_manifest.nil?
          begin
            manifest = MultiXml.parse(version.package_manifest.force_encoding("UTF-8").delete("\t")).with_indifferent_access
          rescue MultiXml::ParseError => e
            log(msg: "failed parsing manifest for version id #{version.id} with error : #{e.message}")
          end

          if manifest.present?
            repository = manifest.dig(:package, :metadata, :repository)
            if repository.present?
              if repository.is_a?(String)
                nuget_metadata_repository = {
                  type: "git",
                  url: repository
                }
              elsif repository.is_a?(Array)
                repository.reverse_each do |repo|
                  if !(repo.nil?)
                    nuget_metadata_repository = { type: repo[:type].present? ? repo[:type].to_s : "git", url: repo[:url], branch: repo[:branch], commit: repo[:commit] }
                    break if repo[:url].present?
                  end
                end
              else
                nuget_metadata_repository = {
                  type: repository.dig(:type).to_s,
                  url: repository.dig(:url),
                  branch: repository.dig(:branch),
                  commit: repository.dig(:commit)
                }
              end
            end
          end
        end

        metadata.each do |key, value|
          # force encode for special characters in metadata
          metadata[key] = value.present? ? value.to_s.force_encoding("UTF-8") : value
        end

        {
          id: version.package.name,
          authors: metadata["Authors"],
          copyright: metadata["Copyright"],
          dependency_groups: metadata["DependencyGroups"],
          dependencies: metadata["Dependencies"],
          description: metadata["Description"],
          icon_url: metadata["IconUrl"],
          language: metadata["Language"],
          license_url: metadata["LicenseUrl"],
          owners: metadata["Owners"],
          project_url: metadata["ProjectUrl"],
          repository: nuget_metadata_repository,
          release_notes: metadata["ReleaseNotes"],
          require_license_acceptance: metadata["RequireLicenseAcceptance"] == "true",
          is_prerelease: metadata["IsPrerelease"] == "true",
          summary: metadata["Summary"],
          tags: metadata["Tags"],
          title: metadata["Title"],
          version: version.version,
          verbatim_version: metadata["VerbatimVersion"],
          readme: metadata["Readme"],
          repo: version.package.owner.login + "/" + version.package.repository.name,
          manifest: version.package_manifest,
          release_id: version.release_id,
          commit_oid: version.commit_oid
        }
      end

      def serialize_container_metadata(version)
        ## validing manifest as some versions of package have empty manifest
        validate_field(name: "container_metadata.manifest", value: version&.package_manifest)
        manifest = JSON.parse(version&.package_manifest).with_indifferent_access

        config = {
          digest: manifest.dig(:config, :digest),
          media_type: manifest.dig(:config, :mediaType),
          size: manifest.dig(:config, :size)
        }

        config.each { |key, val| validate_field(name: "container_metadata.manifest.config.#{key}", value: val) }

        layers = []

        manifest.fetch(:layers, []).each do |l|

          layer = {
            digest: l.dig(:digest),
            media_type: l.dig(:mediaType),
            size: l.dig(:size)
          }

          layer.each { |key, val| validate_field(name: "container_metadata.manifest.layer.#{key}", value: val) }

          layers.append(layer)
        end

        m = {
          digest: "sha256:#{version&.sha256}",
          media_type: manifest.dig(:mediaType),
          size: config[:size] + layers.sum(&:size)
        }

        m.each { |key, val| validate_field(name: "container_metadata.manifest.#{key}", value: val) }

        {
          manifest: m.merge(
            config: config,
            layers: layers
          )
        }
      end

      def serialize_blob_store_paths_docker(serialized_package:, serialized_version:)
        paths = {}

        repo_id = serialized_package.dig(:repo_id)
        manifest = serialized_version.dig(:container_metadata, :manifest)

        add_path = ->(sha:) { paths[sha] = "#{repo_id}/#{get_file_guid(repo_id: repo_id, sha256: sha)}" }

        add_path.call(sha: manifest.dig(:config, :digest))
        manifest.fetch(:layers, []).each { |layer| add_path.call(sha: layer.dig(:digest)) }

        raise MissingDataError.new "no files found for version" if paths.size == 0

        paths
      end

      def serialize_blob_store_paths_for_eco(version)
        repo_id = version.package.repository_id
        guids = version.files.pluck(:guid)
        paths = guids.reduce({}) { |acc, guid| acc[guid] = "#{repo_id}/#{guid}"; acc }

        raise MissingDataError.new "no files found for version" if paths.size == 0
        paths
      end
    end
  end
end
