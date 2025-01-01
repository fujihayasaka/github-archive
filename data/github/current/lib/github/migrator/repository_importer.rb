# typed: true
# frozen_string_literal: true

require "github/dgit/import"

module GitHub
  class Migrator
    class RepositoryImporter < GitHub::Migrator::Importer
      include RepoHelpers
      include GitHub::Rsync

      class FailedRepositoryCreationError < StandardError; end
      class InvalidTarballUrl < StandardError; end
      class UnableToClean < StandardError; end

      class RepositoryImportError < StandardError
        class MaxTimeoutError < RepositoryImportError; end
        class FailedMigration < RepositoryImportError; end
      end

      # List of additional rsync command options to use during import
      RSYNC_IMPORT_OPTIONS = %w(--whole-file).freeze

      GIT_URL_TEMPLATE = Addressable::Template.new("tarball://root/repositories/{org}/{repo}.git").freeze
      GIT_URL_INVALID_SEGMENTS = [nil, ".", ".."].freeze
      TESTING_POLLING_TIMEOUT = 2.hours
      PRODUCTION_POLLING_TIMEOUT = 2.days

      # Public: Used in GitHub::Migrator to raise warnings immediately if the
      # repository has a wiki and the migration schema version is 1.0.0 where
      # the wiki git data wasn't archived correctly.
      #
      # attributes - Hash of attributes for the repository.
      # options    - Hash with `schema_version`.
      #
      # Returns an Array.
      def self.warnings_for(attributes, options = {})
        schema_version = options.fetch(:schema_version)
        if schema_version == "1.0.0" && attributes["wiki_url"].present?
          ["Wiki for #{attributes["url"]} has the wrong content. Use a newer version of gh-migrator to export a new archive."]
        else
          []
        end
      end

      # Public: Imports repository with the following procedure:
      #
      # 1. Create the Repository record and empty bare repo.
      # 2. Build array of importable objects (repo & wiki if present).
      # 3. Migrate svn mappings for each import object if needed.
      # 4. Import each importable object to the appropriate fileservers.
      # 5. Finish preparing the repo by clearing ref cache, setting the default
      #    branch, and locking the repo so that it can be audited before use.
      #
      # attributes - Hash of attributes for the repository.
      # options    - Hash with `target_url` if repository is being renamed.
      #
      # Returns a Repository.
      def import(attributes, options = {})
        unless import_allowed?
          raise "Imports to github.com are not allowed."
        end

        owner = model_from_source_url!(attributes["owner"])

        repo_params = {
          owner: owner,
          name: last_part_of_url(options[:target_url]) || attributes["name"],
          description: attributes["description"]&.truncate(Repository::DESCRIPTION_CHAR_LIMIT, separator: " "),
          public: import_as_public?(attributes),
          homepage: attributes["website"],
          has_issues: attributes["has_issues"],
          has_wiki: attributes["has_wiki"],
          has_downloads: attributes["has_downloads"],
          labels: [],
          created_at: attributes["created_at"],
        }
        repo_params.merge!(created_by_user_id: @actor.id) if @actor

        result = Repository.handle_creation(
          @actor,
          owner.login,
          repo_params,
          skip_validation: true
        )
        repo = result.repository
        if !result.success?
          # Report validation errors if any and fall back to repo creation errors
          validation_or_creation_error_messages = result.repository.errors.full_messages.join(", ").presence || result.error_message
          raise FailedRepositoryCreationError.new(validation_or_creation_error_messages) unless repo.errors[:name].present?

          repo.errors.delete(:name)
          repo.errors.add("name", "(#{repo.name}) already exists on this account")
          raise ActiveRecord::RecordInvalid.new(repo)
        end

        # disables actions on the target repo so they will not run automatically after import
        # https://github.com/github/git-import/issues/237
        repo.disable_actions(actor: repo.owner)

        if GitHub.anonymous_git_access_enabled? && attributes["anonymous_access_enabled"]
          repo.enable_anonymous_git_access(@actor)
        end

        Array(attributes["labels"]).each do |label_attributes|
          begin
            new_label = repo.labels.create!(
              name:       label_attributes["name"],
              color:      label_attributes["color"],
              created_at: label_attributes["created_at"],
            )
          rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => exception
            GitHub.logger.info(
              "code.function": __method__,
              "code.namespace": "GitHub::Migrator::RepositoryImporter",
              "gh.migration_tools.migration.model.name": "repository",
              "gh.migration_tools.migration.model.source_url": attributes["url"],
              "gh.migration_tools.migration.resolution": "Skipped importing label due to: #{exception.message}",
              "gh.migration_tools.migration.guid": migration_guid,
            )
          end
        end

        Array(attributes["collaborators"]).each do |collaborator|
          user = model_from_source_url(collaborator["user"])
          permission = collaborator["permission"]

          if user && permission
            repo.add_member(user, action: permission.to_sym)
          end
        end

        Array(attributes["webhooks"]).each do |webhook|
          payload_url             = webhook["payload_url"]
          content_type            = webhook["content_type"]
          event_types             = webhook["event_types"]
          enable_ssl_verification = webhook["enable_ssl_verification"]
          active                  = webhook["active"]

          if payload_url && content_type && event_types && active
            begin
              if repo.repo_hook_associations_ff?
                Hook.create!(
                  installation_target: repo,
                  name:   "web",
                  active: active,
                  config: {
                    "url"          => payload_url,
                    "insecure_ssl" => enable_ssl_verification ? "0" : "1",
                    "content_type" => content_type,
                  },
                  events: event_types,
                )
              else
                repo.hooks.create!(
                  name:   "web",
                  active: active,
                  config: {
                    "url"          => payload_url,
                    "insecure_ssl" => enable_ssl_verification ? "0" : "1",
                    "content_type" => content_type,
                  },
                  events: event_types,
                )
              end
            rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => exception
              GitHub.logger.info(
                "code.function": __method__,
                "code.namespace": "GitHub::Migrator::RepositoryImporter",
                "gh.migration_tools.migration.model.name": "repository",
                "gh.migration_tools.migration.model.source_url": attributes["url"],
                "gh.migration_tools.migration.resolution": "Skipped importing webhook due to: #{exception.message}",
                "gh.migration_tools.migration.guid": migration_guid,
              )
            end
          end
        end

        Array(attributes["public_keys"]).each do |public_key|
          title       = public_key["title"]
          key         = public_key["key"]
          read_only   = public_key["read_only"]
          created_at  = public_key["created_at"]

          if title && key && created_at
            begin
              repo.public_keys.create!(
                title:      title,
                key:        key,
                read_only:  read_only,
                created_at: created_at,
              )
            rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => exception
              if exception.record.errors.messages == { key: ["is already in use"] }
                fingerprint = exception.record.fingerprint
                resolution = "Skipped public key with fingerprint #{fingerprint} (already in use)"
              else
                resolution = "Skipped public key due to: #{exception.message}"
              end
              GitHub.logger.info(
                "code.function": __method__,
                "code.namespace": "GitHub::Migrator::RepositoryImporter",
                "gh.migration_tools.migration.model.name": "repository",
                "gh.migration_tools.migration.model.source_url": attributes["url"],
                "gh.migration_tools.migration.resolution": resolution,
                "gh.migration_tools.migration.guid": migration_guid,
              )
            end
          end
        end

        begin
          # Build array of git repos to import (the repository and maybe its wiki).
          imports = []
          imports << ImportableRepository.new(repo, path_to_bare_repo(attributes["git_url"]), attributes["url"])

          # Only do wiki things if wiki is present in migration archive.
          if wiki_url = attributes["wiki_url"]
            # Prepare the UnsulliedWiki object and RepositoryWiki record.
            repo.unsullied_wiki.setup_git_repository
            begin
              RepositoryWiki.create(repository: repo)
            rescue ActiveRecord::RecordNotUnique => exception
              GitHub.logger.info(
                "code.function": __method__,
                "code.namespace": "GitHub::Migrator::RepositoryImporter",
                "gh.migration_tools.migration.model.name": "repository",
                "gh.migration_tools.migration.model.source_url": attributes["url"],
                "gh.migration_tools.migration.resolution": "Skipped importing the repository wiki due to: #{exception.message}",
                "gh.migration_tools.migration.guid": migration_guid,
              )
            end
            repo.reload

            imports << ImportableWiki.new(repo, path_to_bare_repo(wiki_url), attributes["url"])
          end

          gsm_import_enabled = GitHub.flipper[:import_export_eci_import_with_gsm].enabled?(repo.owner)
          use_dgit_import = GitHub.enterprise? || !gsm_import_enabled

          if use_dgit_import
            import_to_dgit_fileservers repo, imports
          else
            import_via_gsm(repo, options, attributes)
          end


          # Setting default branch doesn't work without clearing the ref cache
          # first and this seems like a healthy thing to do anyways after rsyncing
          # the git data.
          repo.clear_ref_cache

          # Set the default branch if the serialized repository data has it.
          if default_branch = attributes["default_branch"]
            repo.update_default_branch(default_branch)
          end

          repo.lock_for_migration
          repo.update_disk_usage
          repo
        rescue SvnMappingError, DGitImportError => error
          # Attempt to cleanup failed repository import so that rerunning import
          # for same migration can pick back up at the failed repository and try
          # again rather than failing with class="ActiveRecord::RecordInvalid"
          # message="Validation failed: Name already exists on this account" error.
          repo.destroy

          raise error
        end
      end

      attr_writer :dgit_logger

      private

      # Internal: Logger for dgit import logging.
      def dgit_logger
        @dgit_logger ||= Rails.logger
      end

      # Internal: Determine public/private settings for repository import.
      # If we're importing into Enterprise, read in the setting from archive.
      # If we're importing into GitHub.com, ALWAYS import as private
      def import_as_public?(attributes)
        return false unless GitHub.enterprise?
        !attributes["private"]
      end

      # Internal: Rsync importable objects to non-dgit fileserver.
      #
      # imports - Array with ImportableRepository and ImportableWiki if it exists.
      def rsync_to_fileserver(imports)
        imports.each do |import|
          target = import.record

          rsync \
            from: import.source_path,
            to: local_route?(target) ? target.shard_path : "git@#{target.resolved_host}:#{target.shard_path}",
            exclude: RSYNC_IMPORT_EXCLUDES
        end
      end

      # Internal: Imports importable objects to dgit fileservers with the
      # following procedure:
      #
      # 1. Prepare destination directories, usually the network shard path with
      #    the ".premove" suffix and then prepopulate those directories with
      #    the auto initialized git data.
      # 2. Take the repository offline while it is being updated.
      # 3. Rsync importable data from migration staging area to destinations.
      # 4. Checksum the network across dgit fileservers.
      # 5. Initialize dgit for the network.
      # 6. Move original network out of the way and then move the premove
      #    destination directories to the original network paths.
      # 7. Put the repository back online.
      #
      # repo    - Repository that importable objects are associated with.
      # imports - Array with ImportableRepository and ImportableWiki if it exists.
      def import_to_dgit_fileservers(repo, imports)
        cleaner = Cleaner.new
        if cleaner.enabled?(repo: repo, actor: @actor)
          imports.each do |import|
            log_fields = {
              "code.function": "import_to_dgit_fileservers",
              "code.namespace": "GitHub::Migrator::RepositoryImporter",
              "gh.migration_tools.migration.type": "repo",
              "gh.migration_tools.migration.model.source_url": import.source_url,
              "gh.migration_tools.migration.guid": migration_guid,
            }
            stats_tags = {
              importable_type: import.class.name.demodulize,
            }
            start_clean = GitHub::Dogstats.monotonic_time
            begin
              cleaner.clean!(import.source_path, skip_repack: cleaner.skip_repack?(repo: repo))
              GitHub.logger.info("Cleaning repository before rsync succeeded", log_fields)
              stats_tags[:result] = "success"
            rescue UnableToClean => e
              stats_tags[:result] = "error"
              GitHub.logger.error("Cleaning repository before rsync failed", log_fields.merge(exception: e))
              raise UnableToClean, "repository #{import.source_url} was not valid"
            ensure
              now = GitHub::Dogstats.monotonic_time
              GitHub.dogstats.distribution("migrator.import.repository_cleaner.time", GitHub::Dogstats.duration(start_clean, now), tags: stats_tags)
            end
          end
        end

        routes = repo.dgit_all_routes

        network_id = repo.network_id
        network_shard_path = GitHub::Routing.nw_storage_path(network_id: network_id).chomp("/")
        premove = ".premove" unless Rails.env.development? || GitHub.enterprise?

        # prepare rsync target directories
        if premove.present?
          kids = GitHub::DGit::Import::parallelize(dgit_logger, routes) do |route|
            source = source_path(network_shard_path, best_host(route))

            premove_dest = "#{source}#{premove}"

            dgit_logger.info "Copying repo to #{premove_dest}"
            if local_route?(route)
              if !File.exist?(source)
                raise DGitImportError.new("source directory does not exist")
              end

              if File.exist?(premove_dest)
                raise DGitImportError.new("premove directory already exists")
              end

              # copy the (empty) repository network to the .premove location
              ["cp -R #{source} #{premove_dest}"]
            else
              "ssh #{route.resolved_host} gh_migrator_prepare_network_premove #{source}"
            end
          end
          if kids.any? { |_host, kid| kid.status.exitstatus != 0 }
            raise DGitImportError.new("premove preparation failure\n#{error_message_from_kids(kids)}")
          end
        end

        # Offline the repository while we move bits to it.
        GitHub::DGit::Import::set_moving(dgit_logger, network_id, 1)

        # Rsync importable data from migration staging area to destinations.
        imports.each do |info|
          target = info.record

          kids = GitHub::DGit::Import::parallelize(dgit_logger, info.destination_routes) do |route|
            dest = "#{source_path(network_shard_path, best_host(route))}#{premove}"

            rsync_command \
              from: info.source_path,
              to: local_route?(route) ? info.destination_path(dest) : "git@#{route.resolved_host}:#{info.destination_path(dest)}",
              options: RSYNC_IMPORT_OPTIONS,
              exclude: RSYNC_IMPORT_EXCLUDES
          end
          if kids.any? { |_host, kid| kid.status.exitstatus != 0 }
            GitHub::DGit::Import::set_moving(dgit_logger, network_id, 0)
            raise DGitImportError.new("failed to rsync git data\n#{error_message_from_kids(kids)}")
          end
        end

        # Create `dgit-state` checksum files and capture their contents
        checksums = GitHub::DGit::Import::git_dgit_state_init \
          dgit_logger, "localhost", routes.map(&method(:best_host)), GitHub::DGit::RepoType::REPO,
          network_id, network_shard_path

        if !checksums || !checksums[GitHub::DGit::RepoType::REPO] || !checksums[GitHub::DGit::RepoType::WIKI]
          GitHub::DGit::Import::set_moving(dgit_logger, network_id, 0)
          raise DGitImportError.new("DGit state and checksum initialization failure")
        end

        if premove.present?

          kids = GitHub::DGit::Import::parallelize(dgit_logger, routes) do |route|
            dest = source_path(network_shard_path, best_host(route))

            command = local_route?(route) ? [] : ["ssh", route.resolved_host]
            command + ["mv", dest, "#{dest}.moved"]
          end
          if kids.any? { |_host, kid| kid.status.exitstatus != 0 }
            GitHub::DGit::Import::set_moving(dgit_logger, network_id, 0)
            raise DGitImportError.new("network pre-migration move failure\n#{error_message_from_kids(kids)}")
          end

          # Move "<networkid>.premove" to "<networkid>"
          kids = GitHub::DGit::Import::parallelize(dgit_logger, routes) do |route|
            dest = source_path(network_shard_path, best_host(route))

            if local_route?(route)
              ["mv", "#{dest}#{premove}", dest]
            else
              ["ssh", route.resolved_host, "finalise_network_move2", dest]
            end
          end
          if kids.any? { |_host, kid| kid.status.exitstatus != 0 }
            GitHub::DGit::Import::set_moving(dgit_logger, network_id, 0)
            raise DGitImportError.new("finalize network move failure\n#{error_message_from_kids(kids)}")
          end
        end

        # set moving=0
        GitHub::DGit::Import::set_moving(dgit_logger, repo.network_id, 0)

        # Clean up .moved folders
        non_local_routes = routes.reject(&method(:local_route?))
        kids = GitHub::DGit::Import::parallelize(dgit_logger, non_local_routes) do |route|
          ["ssh", route.resolved_host, "clean_network", network_id.to_s]
        end
        if kids.any? { |_host, kid| kid.status.exitstatus != 0 }
          dgit_logger.info("clean network failure\n#{error_message_from_kids(kids)}")
        end

        # Disable debug checksum logging
        GitHub.dgit_threepc_debug_enabled = false

        # Recompute checksums
        imports.each { |i| i.record.recompute_checksums(:vote, nil) }
      ensure
        # Re-enable debug checksum logging
        GitHub.dgit_threepc_debug_enabled = true
      end

      # Internal: Convert repository or wiki git data url into the full path to
      # the git data on disk, i.e. tarball://root/repositories/acme/widgets.git
      # returns repositories/acme/widgets.git.
      #
      # tarball_url - String.
      #
      # Returns a String.
      def path_to_bare_repo(tarball_url)
        git_url_template_match = GIT_URL_TEMPLATE.match(tarball_url)

        catch :invalid_url do
          throw :invalid_url unless git_url_template_match

          %w{org repo}.each do |segment|
            throw :invalid_url if GIT_URL_INVALID_SEGMENTS.include?(git_url_template_match[segment])
          end

          return File.join(
            migration_path,
            "repositories",
            git_url_template_match["org"],
            "#{git_url_template_match["repo"]}.git"
          )
        end

        raise(InvalidTarballUrl, "Invalid tarball URL: #{tarball_url}")
      end

      # Internal: Collect err and out from kids and compile into string.
      #
      # kids - Array of BackgroundChild instances.
      #
      # Returns a String.
      def error_message_from_kids(kids)
        kids.inject([]) { |result, (_host, kid)| result << "CMD:\n#{kid.cmd}\nOUT:\n#{kid.out}\nERR:\n#{kid.err}" }.join("\n")
      end

      def import_via_gsm(repo, options, attributes)
        gsm_import = ::GitSourceMigratorImport.new(
          user: @actor,
          repository: repo,
          client_source_type: :CLIENT_SOURCE_TYPE_ECI
        )

        begin
          source_type = case options[:migration_source]
          when "GitLab"
            :SOURCE_TYPE_GITLAB
          when "BitBucket"
            :SOURCE_TYPE_BITBUCKET_SERVER
          when "GitHub"
            :SOURCE_TYPE_GITHUB
          else
            :SOURCE_TYPE_INVALID
          end

          import_params = {
            source_url: attributes["url"],
            source_type: source_type,
            git_archive_url: options[:archive_download_url],
            archive_format: :ARCHIVE_FORMAT_GITHUB
          }

          if attributes["wiki_url"]
            wiki = repo.unsullied_wiki
            import_params[:target_wiki_ssh_url] = wiki.ssh_url if wiki
          end

          gsm_id_response = gsm_import.start_import(**import_params)
          GitHub.dogstats.increment("eci.gsm.migration.started")

          sleep_time = 10
          max_poll_time = if Rails.env.development? || GitHub.review_lab?
            TESTING_POLLING_TIMEOUT
          else
            PRODUCTION_POLLING_TIMEOUT
          end
          start_time = Time.now

          loop do
            elapsed_time = Time.now - start_time
            status = gsm_import.status

            if :MIGRATION_STATE_SUCCEEDED == status.state
              break
            end

            if [:MIGRATION_STATE_FAILED, :MIGRATION_STATE_FAILED_VALIDATION].include?(status.state)
              error_message = status.failure_reason
              error_message = "An unknown error occurred in the git source migration." if error_message.blank?
              error_details = status.error_details

              raise RepositoryImportError::FailedMigration, error_message
            end

            if elapsed_time > max_poll_time
              raise RepositoryImportError::MaxTimeoutError, "Git Source Migrator max timeout of 2 days reached"
            end

            sleep(sleep_time)
          end
        rescue RepositoryImportError, ::GitSrcMigrator::Twirp::Error, Faraday::Error => e
          tags = ["rpc:start_migration", "error:#{e.class}"]
          GitHub.dogstats.increment("eci.gsm.migration.failed", tags: tags)
          GitHub.dogstats.increment("eci.gsm.unavailable", tags: tags) unless gsm_id_response

          # Attempt to cleanup failed repository import so that rerunning import
          # for same migration can pick back up at the failed repository and try
          # again rather than failing with class="ActiveRecord::RecordInvalid"
          # message="Validation failed: Name already exists on this account" error.
          begin
            repo.destroy
          rescue
            GitHub.dogstats.increment("eci.gsm.migration.repository_cleanup_failed", tags:)
          end

          raise RepositoryImportError, "GSM migration with id #{gsm_id_response} failed: #{e.message}" if gsm_id_response
          raise RepositoryImportError, "GSM migration failed: #{e.message}"
        end
      end

      # Internal: Return network source path appropriate for current environment.
      #
      # network_shard_path - String path.
      # host               - String host where path should exist.
      #
      # Returns a String.
      def source_path(network_shard_path, host)
        if Rails.env.production?
          network_shard_path
        else
          GitHub::DGit::dev_route(network_shard_path, host)
        end
      end

      # Internal: Determines if the provided route is local
      #
      # route - The route to check against
      #
      # Returns a boolean
      def local_route?(route)
        # This class may need to locally access repositories outside of normal
        # configurations.  It's likely host is only "localhost" in
        # development/test but it's difficult to tell.
        route.host == "localhost" || GitHub::DGit.local_access?(route.host)
      end

      def best_host(route)
        if local_route?(route)
          route.original_host
        else
          route.resolved_host
        end
      end

      # Internal: List of rsync exclusions.
      #
      # Push (nearly) everything into the new repository.
      # * Exclude 'hooks/' and 'config' so that we keep the target's settings.
      # * Exclude 'info/' and 'description' because they probably have wrong info for the new instance.
      RSYNC_IMPORT_EXCLUDES = %w(/hooks /config /info /description /commondir).map(&:freeze).freeze

      class ImportableRepository
        def initialize(repo, source_path, source_url)
          @repo        = repo
          @source_path = source_path
          @source_url  = source_url
        end

        attr_reader :repo, :source_path, :source_url

        def record
          repo
        end

        def destination_routes
          repo.dgit_all_routes
        end

        def destination_path(dest)
          "#{dest}/#{repo.id}.git"
        end
      end

      class ImportableWiki
        def initialize(repo, source_path, source_url)
          @repo        = repo
          @source_path = source_path
          @source_url  = source_url
        end

        attr_reader :repo, :source_path, :source_url

        def record
          repo.unsullied_wiki
        end

        def destination_routes
          repo.dgit_wiki_write_routes # this will raise GitHub::DGit::UnroutedError if no wiki routes are found
        end

        def destination_path(dest)
          "#{dest}/#{repo.id}.wiki.git"
        end
      end

      # The contents of a Git repository in an import archive might have
      # anything inside. Let's clean it up before rsync'ing to our github-dfs
      # hosts.
      class Cleaner
        def enabled?(repo:, actor:)
          return true if GitHub.flipper[:gh_migrator_clean_repositories].enabled?(repo.owner)
          return true if GitHub.flipper[:gh_migrator_clean_repositories].enabled?(@actor)
          false
        end

        def skip_repack?(repo:)
          return true if GitHub.flipper[:gh_migrator_clean_repositories_skip_repack].enabled?(repo.owner)
          return true if GitHub.flipper[:gh_migrator_clean_repositories_skip_repack].enabled?(@actor)
          false
        end

        def clean!(source_path, skip_repack: false)
          root_dir = File.expand_path(File.dirname(source_path))
          basename = File.basename(source_path)
          tainted_path = File.join(root_dir, "tainted-#{basename}")

          verify_no_symlinks(source_path)
          verify_plausible_repo(source_path)

          File.rename(source_path, tainted_path)
          remove_config(tainted_path)
          remove_alternates(tainted_path)

          safe_clone(from: tainted_path, to: source_path, chdir: root_dir)

          repack(source_path) unless skip_repack
          remove_remote_refs(source_path)
          pack_refs(source_path)

          true
        ensure
          if tainted_path
            system "rm", "-rf", tainted_path
          end
        end

        private

        def verify_no_symlinks(path)
          paths = [path]
          until paths.empty?
            path = paths.shift
            info = File.stat(path)
            if info.symlink?
              # Don't allow any symlinks in the repository.
              raise UnableToClean, "refuse to import repository with symlink at #{path}"
            end
            if info.directory?
              Dir.glob(File.join(path, "*"), File::FNM_DOTMATCH).each do |child_path|
                unless child_path.end_with?("/.", "/..")
                  paths << child_path
                end
              end
            end
          end
        end

        def verify_plausible_repo(git_dir)
          # Make sure "HEAD" is a regular file and at least contains "ref: refs/"
          head_stat = File.stat(File.join(git_dir, "HEAD"))
          if !head_stat.file? || head_stat.size < 10
            raise UnableToClean, "gh-migrator repository cleaner: #{git_dir}: not a valid Git repository: invalid HEAD"
          end

          # Make sure "objects" and "refs" are directories.
          if !File.directory?(File.join(git_dir, "objects"))
            raise UnableToClean, "gh-migrator repository cleaner: #{git_dir}: not a valid Git repository: missing objects"
          end
          if !File.directory?(File.join(git_dir, "refs"))
            raise UnableToClean, "gh-migrator repository cleaner: #{git_dir}: not a valid Git repository: missing refs"
          end

          true
        end

        def remove_config(git_dir)
          File.unlink(File.join(git_dir, "config"))
        rescue Errno::ENOENT
          # ok
        end

        def remove_alternates(git_dir)
          File.unlink(File.join(git_dir, "objects/info/alternates"))
        rescue Errno::ENOENT
          # ok
        end

        def safe_clone(from:, to:, chdir:)
          # From https://git-scm.com/docs/git#_security:
          #
          #   If you have an untrusted .git directory, you should first clone
          #   it with git clone --no-local to obtain a clean copy.
          out, ok = run("git", "clone", "--no-local", "--mirror", "--quiet", from, to, chdir: chdir)
          if !ok
            raise UnableToClean, "gh-migrator repository cleaner: git clone failed\noutput:\n#{out}"
          end
        end

        def repack(git_dir)
          out, ok = run("git", "-c", "pack.windowMemory=1500m", "--git-dir", git_dir, "gc", "--aggressive", "--quiet", chdir: git_dir)
          if !ok
            raise UnableToClean, "gh-migrator repository cleaner: repack failed\noutput:\n#{out}"
          end
        end

        # remove_remote_refs removes all references under refs/remotes/.
        def remove_remote_refs(git_dir)
          # Remove all refs/remotes/*. These don't make sense on the server,
          # and they usually have a symbolic ref (which we don't want on
          # github-dfs hosts).
          er, ew = IO.pipe
          et = Thread.new(er) { |er| er.read } # rubocop:disable GitHub/ThreadUse
          r, w = IO.pipe
          pid1 = Process.spawn("git", "for-each-ref", "refs/remotes", "--format", "delete %(refname)",
            chdir: git_dir,
            out: w,
            err: ew)
          w.close
          pid2 = Process.spawn("git", "update-ref", "--stdin",
            chdir: git_dir,
            in: r,
            out: ew,
            err: ew)
          r.close
          ew.close
          _, for_each_ref_status = T.must(Process.wait2(pid1))
          _, update_ref_status = T.must(Process.wait2(pid2))
          out = et.value
          if !for_each_ref_status.success?
            raise UnableToClean, "gh-migrator repository cleaner: for-each-ref returned an error: #{for_each_ref_status.inspect}\noutput:\n#{out}"
          end
          if !update_ref_status.success?
            raise UnableToClean, "gh-migrator repository cleaner: update-ref returned an error: #{update_ref_status.inspect}\noutput:\n#{out}"
          end
        end

        def pack_refs(source_path)
          out, ok = run("git", "--git-dir", source_path, "pack-refs", "--all", chdir: source_path)
          if !ok
            raise UnableToClean, "gh-migrator repository cleaner: pack-refs failed\noutput:\n#{out}"
          end
        end

        # Run runs a command, returns its output and whether the command exited
        # with success.
        #
        # The arguments are a list of args to spawn (cmd) and a directory where
        # the program will be run.
        #
        # Return value is an array with two elements:
        # - (String) combined stdout and stderr.
        # - (boolean) true if the program ran successfully.
        def run(*cmd, chdir:)
          opts = { chdir: chdir }
          # "Sorbet does not have great support for splats right now." https://srb.help/7019
          child = T.unsafe(Progeny::Command).new(*(cmd + [opts]))
          separator = (child.out.blank? || child.err.blank? || child.out.end_with?("\n")) ? "" : "\n"
          combined_output = "#{child.out}#{separator}#{child.err}"
          [combined_output, child.success?]
        end
      end
    end
  end
end
