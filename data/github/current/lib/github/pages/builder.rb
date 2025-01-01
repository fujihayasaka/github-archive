# typed: false
# frozen_string_literal: true

module GitHub
  module Pages
    class Builder
      class Error < StandardError; end # Generic build error
      class UserError < StandardError; end # Detected, user-caused build error
      class BuildTimeout < StandardError; end # The build timed-out
      class SyncTimeout < StandardError; end # The sync timed-out
      class AuthError < StandardError; end # The build failed to authenticate
      class MissingBuildEnvironment < StandardError; end
      class MissingBuildRevisionError < StandardError; end

      class IncompatibleUserTypeError < UserError; end # This build was started by a bot or org

      class NoInstallationError < StandardError; end
      class GitHubAppError < StandardError; end

      PASSTHROUGH_ERRORS_TO_USER = [Error, UserError, BuildTimeout, SyncTimeout].freeze
      CHECK_FAILURE_TITLE = "GitHub Pages failed to build your site."
      BUILD_TIMEOUT_ERROR = "The GitHub Pages build timed out. Please try again later."

      USERNAME = "git".freeze
      AUTH_ERROR_MESSAGE = "Invalid username or password.".freeze
      BUILD_TRIES = 5 # Maximum number of times we try to clone a Pages branch
      BUILD_SLEEP_TIME = 2 # Number of seconds to wait for DB replicas to catch up to the primary
      COMMAND_TRIES = 5 # Maximum number of times we retry any command
      COMMAND_RETRIES_SLEEP = 2 # Number of seconds to wait before retrying any command.

      CODEPATH_PAGES_BUILDER = "pages/pages_github_app_token".freeze

      # Public: Initialize a new Pages Builder.
      #
      # page         - a Page instance to build
      # pusher       - a User instance who initiated the build
      # build_dir    - a String pathname to a build directory
      # git_ref_name - (named, optional) a String git reference name (e.g. a branch name)
      #                that the builder should check out before executing the compilation process.
      #                If it is not specified, the Builder uses the Repository pages_branch.
      #                Note that this should be an unqualified branch name, e.g. 'gh-pages'.
      #                It should *not* contain 'refs/heads/' or anything similar.
      def initialize(page, pusher, build_dir, git_ref_name: nil)
        @page = page
        @pusher = pusher
        @build_dir = build_dir
        @git_ref_name = git_ref_name || page.source_branch
        @oauth_token = nil
        @enterprise_build_client = GitHub::Pages::EnterpriseBuilderApiClient.new
        @replicator = GitHub::Pages::Replicator.new(page.repository)
        @page_size = 0
        @page_file_count = 0

        # the pages sync host, can only be set by dpages sync method.
        @successful_hosts = []
      end

      def should_use_apps?
        return @should_use_apps if defined?(@should_use_apps)

        @should_use_apps = (pages_github_app_enabled?(@page.repository) && pages_github_app_token.present?)
      end

      def feature_enabled?(feature, repository)
        return false if GitHub.enterprise?
        return false if repository.nil?

        @feature_enabled = {}
        key = "#{repository.id}_#{feature}"

        return @feature_enabled[key] if @feature_enabled.key?(key)

        @feature_enabled[key] = GitHub.flipper[feature].enabled?(repository) ||
          GitHub.flipper[feature].enabled?(repository.owner)
      end

      def pages_statuses_enabled?(repository)
        !GitHub.enterprise? && repository.present?
      end

      def pages_features_checks_api_enabled?
        !GitHub.enterprise?
      end

      def pages_github_app_enabled?(repository)
        feature_enabled?(:pages_github_app, repository)
      end

      def pages_beta_image?(repository)
        feature_enabled?(:pages_beta_image, repository) &&
          !repository.nwo.eql?("github/pages.github.com")
      end

      def pages_recycle_enabled?(repository)
        return false if GitHub.enterprise? && !GitHub.kube?

        # enable pages recycle when feature flag enabled and not first time deployment.
        (GitHub.kube? || feature_enabled?(:pages_build_recycle, repository)) && !page_deployment.revision.nil?
      end

      def validate_can_issue_oauth_access!
        return nil if @pusher.present? && @pusher.user?
        raise IncompatibleUserTypeError, "GitHub Pages builds cannot be executed by #{@pusher.class} accounts."
      end

      def pages_oauth_access
        validate_can_issue_oauth_access!
        @pages_oauth_access ||=
          begin
            oauth_access = @pusher.oauth_accesses.find_by_application_id(GitHub.pages_app_id)

            if oauth_access.nil?
              oauth_access = @pusher.oauth_accesses.new(
                application_id: GitHub.pages_app_id,
                application_type: "OauthApplication",
                scopes: ["repo"],
              )
            end

            oauth_access
          end
      end

      def pages_github_app_installation
        return nil unless GitHub.pages_github_app.present?
        @installation ||= IntegrationInstallation
          .with_repository(@page.repository)
          .where(integration_id: GitHub.pages_github_app.id)
          .first
      end

      def pages_github_app_token
        return nil unless pages_github_app_installation.present?
        @app_token ||=
          begin
            result = ScopedIntegrationInstallation::Creator
              .perform(pages_github_app_installation, repositories: [@page.repository], entry_point: :pages_builder_github_app_token)

            if result.failed?
              report_error_to_failbot(
                ScopedIntegrationInstallation::Result::Error.new(
                  result.error,
                ),
              )
              return nil
            end
            _, token = AuthenticationToken.create_for(result.installation, code_path: CODEPATH_PAGES_BUILDER)
            token
          end
      end

      def oauth_token
        return nil if should_use_apps?
        @oauth_token ||=
          begin
            # Older tokens will have a code set that is not needed.
            pages_oauth_access.code = nil
            pages_oauth_access.reset_token
          end
      end

      def sanitize_command(command)
        return if command.empty?
        command.map do |part|
          filter_tokens(part)
        end
      end

      # Generate the oauth token, then wait for replication of the token across DB read replicas.
      # We have a hard requirement on a low replication lag, since we regenerate a new token
      # for every page build. This method gives us a little breathing room when replication delay
      # spikes on our DB cluster.
      def replicate_oauth_token!(max_wait_seconds: 255)
        return 0 unless Rails.env.production? || Rails.env.test? || !should_use_apps?

        _ = oauth_token # This resets the token then stores in an instance variable for later.
        waiter = WaitForReplication.new(Timestamp.from_time(Time.now), max_wait_seconds: max_wait_seconds)

        begin
          waiter.wait!
          log(fn: "replicate_oauth_token!", waited: waiter.waited)
        rescue WaitForReplication::DataUnavailable => e
          log(fn: "replicate_oauth_token!", waited: waiter.waited, error_message: e.message)
        end

        waiter.waited
      end

      def report_build_token
        tag = begin
          if should_use_apps?
            "github-app"
          elsif oauth_token.present?
            "oauth"
          else
            raise GitHubAppError, "No GitHub app or OAuth token available."
          end
        end
        GitHub.dogstats.increment("pages.build_token", tags: ["token:#{tag}"])

        # Temporary investigation to help safely delete Pages full-trust oauth app
        # https://github.com/github/security-iam/issues/3113
        unless GitHub.enterprise? || Rails.env.test?
          GitHub.logger.info({
            "gh.catalog_service" => "github/pages",
            "code.function" => "builder.report_build_token",
            "gh.repo.nwo" => @page.repository.nwo,
            "gh.pages.id" => @page.id,
            "git.ref" => @git_ref_name,
          })
        end
      end

      def report_github_app_bad_state
        if pages_github_app_enabled?(@page.repository)
          if pages_github_app_installation.blank?
            raise NoInstallationError, "The Pages GitHub app is not installed."
          elsif pages_github_app_token.blank?
            raise GitHubAppError, "Pages GitHub app is installed, but the OAuth token will be used."
          end
        end
      rescue NoInstallationError, GitHubAppError => error
        report_error_to_failbot(error)
      end

      # Creates the remote clone url with a GitHub or OAuth app token.
      #
      # Side effect – reports to datadog which token is used.
      # Side effect – reports to failbot if the Pages GitHub app is installed, but an OAuth app is used.
      # Returns – the remote clone url as a String.
      def clone_url_with_token
        scheme = (GitHub.ssl? ? "https" : "http")
        credentials = should_use_apps? ? "x-access-token:#{pages_github_app_token}" : "#{@pusher.login}:#{oauth_token}"
        path = "#{GitHub.host_name}/#{@page.repository.name_with_owner}.git"
        report_build_token
        report_github_app_bad_state
        "#{scheme}://#{credentials}@#{path}"
      end

      def clone_url
        if Rails.env.production?
          clone_url_with_token
        else
          repository.internal_remote_url
        end
      end

      def built_revision(built_result)
        return built_result.commit if built_result.is_a? GitHub::Pages::BuildStatusObject
        return nil unless File.exist?("#{build_path}/pages-build-version")
        File.read("#{build_path}/pages-build-version").strip
      end

      # Gather data in splunk to get
      # exact page build size and count the total number of files under each page build folder
      def build_metrics
        if feature_enabled?(:pages_build_metrics, @page.repository)
          begin
            stats = Dir["#{build_path}/**/*"].select { |f| File.file?(f) }.map { |f| File.size(f) }
            @page_size = stats.sum / 1024
            @page_file_count = stats.length

          rescue StandardError => e # rubocop:todo Lint/GenericRescue
            GitHub.logger.error(e, {
              "gh.catalog_service" => "github/pages",
              "code.function" => "builder.report_build_token",
              "gh.repo.nwo" => @page.repository.nwo,
              "gh.pages.id" => @page.id,
              "git.ref" => @git_ref_name,
            })
          end
        end
      end

      def call
        start_time = Time.now
        raise MissingBuildEnvironment, "build environment is not available" unless build_environment_available? && build_compatible?

        Failbot.push(
          :catalog_service => "github/pages",
          "code.namespace" => "github.pages.builder",
          "code.function" => "builder.call",
          "gh.pages.build.user.path" => build_user_path,
          "gh.pages.build.path" => build_path,
          "gh.pages.deployment.id" => page_deployment.id,
        )
        repository = @page.repository
        # replicas within path to be cleaned after successful build
        if pages_recycle_enabled?(repository)
          recycle_replicas_hosts = ApplicationRecord::Domain::Repositories.connection.select_values(Arel.sql(<<-SQL, page_deployment_id: page_deployment.id, page_id: @page.id))
            SELECT host FROM pages_replicas
            WHERE pages_deployment_id = :page_deployment_id AND
            page_id = :page_id
          SQL
          recycle_revision = page_deployment.revision
          recycle_storage_path = GitHub::Routing.dpages_storage_path(@page.id, revision: recycle_revision)
        end

        @build = Page::Build.track(@page, pusher: @pusher, page_deployment_id: page_deployment.id)
        Failbot.push(
          :catalog_service => "github/pages",
          "code.namespace" => "github.pages.builder",
          "code.function" => "builder.call",
          "gh.pages.build.id" => page_build_id
        )

        begin
          build_process = page_build
        rescue Progeny::TimeoutExceeded, Faraday::TimeoutError
          report_failed_build_to_user
          raise BuildTimeout, "Page build timed out. Please try again later."
        end
        commit = built_revision(build_process)
        @build.update(commit: commit)
        Failbot.push(
          :catalog_service => "github/pages",
          "code.namespace" => "github.pages.builder",
          "code.function" => "builder.call",
          "gh.pages.version" => commit
        )
        if commit.to_s.empty?
          raise MissingBuildRevisionError, "could not fetch commit from built site"
        elsif File.basename(commit) != commit
          raise MissingBuildRevisionError, "contents of pages-build-version #{commit.inspect} contains path separators"
        end

        log_build_step("pages-build-metrics") { build_metrics }

        begin
          log_build_step("dpages-sync") { dpages_sync(revision: commit) }
        rescue Progeny::TimeoutExceeded, Faraday::TimeoutError
          report_failed_build_to_user
          raise SyncTimeout, "Page build timed out. Please try again later."
        end

        @build.complete!((Time.now - start_time) * 1_000)

        # The storage path is in the pattern: /x/.../{page_id}/{built_revision}
        # The page recycle job will remove built_revision folder, but will keep page_id folder even it's potential empty.
        # The reason is due to the recycle job is a background job. We may have page build and recycle job running at the same time, which leads to concurrency issue.
        # see https://github.com/github/github/pull/161209#discussion_r517687372 for more details.
        if pages_recycle_enabled?(repository)
          if GitHub.kube?
            # do not clean the deployment page, if it rebuilds on the current version.
            @enterprise_build_client.page_clean(recycle_storage_path) unless commit == recycle_revision
          else
            recycle_replicas_hosts = recycle_replicas_hosts.reject { |host| @successful_hosts.include?(host) } if commit == recycle_revision
            PageRecycleJob.perform_later(recycle_replicas_hosts, recycle_storage_path)
          end
        end

        # Warn-level build feedback
        # CNAME warnings which may result in the site being built someplace other
        # than expected should take preference over good-to-know warnings like Maruku
        if warning_message = @page.cname_error || warning(build_process.err)
          GitHub.dogstats.increment("pages.warnings")
          PagesMailer.build_warning(@pusher, repository, warning_message, @build).deliver_now
        end

        @build
      rescue Object => err # rubocop:todo Lint/GenericRescue
        duration = (Time.now - start_time) * 1_000
        report_error_to_user(err, duration)
        report_error_to_failbot(err, {
          :catalog_service => "github/pages",
          "code.namespace" => "github.pages.builder",
          "code.function" => "builder.call",
          "gh.exception.create_time" => duration
          })
        @build
      ensure
        if production_environment?
          if GitHub.enterprise?
            @enterprise_build_client.page_clean(build_path)
          else
            # Clean up the build path
            cleanup_script = ["rm -rf #{build_path}"]
            cleanup_script.unshift("sudo -u jekyll")
            run([cleanup_script.join(" ")], "failed to cleanup")

            # Clean up the tar file
            cleanup_script = ["rm -f #{@build_dir}/#{Digest::SHA256.hexdigest build_path}.tar"]
            cleanup_script.unshift("sudo -u jekyll")
            run([cleanup_script.join(" ")], "failed to cleanup")
          end
        else
          # Clean up the local build path
          FileUtils.rm_rf build_path

          # Clean up the local tar file
          FileUtils.rm_rf "#{@build_dir}/#{Digest::SHA256.hexdigest build_path}.tar"
        end
        elapsed = (Time.now - start_time) * 1_000
        GitHub.dogstats.distribution "pages.build.dist", elapsed, tags: ["status:#{@build&.status || "unknown"}"]
        GitHub.logger.info(base_log_data.merge("code.function": "page-build", "elapsed": elapsed).merge(step_times))
      end

      def report_error_to_user(err, duration)
        unless @build
          GitHub.dogstats.increment("pages.builds", tags: ["status:error"])
          return
        end

        # We want to be careful about what messages are sent back to the user.
        # Here, we send an error back if it is a UserError (already sanitized)
        # or an Error (a generic error that has a hand-crafted error message from us).
        return @build.error!(err, duration) if PASSTHROUGH_ERRORS_TO_USER.include?(err.class)

        error = Error.new("Page build failed.")
        error.set_backtrace(err.backtrace)
        @build.error!(error, duration)
      end

      def report_error_to_failbot(err, options = {})
        app = err.is_a?(UserError) ? "pages-user" : "pages"
        Failbot.report(err, options.merge(app: app))
      end

      def dpages_sync(revision:)
        hosts = @replicator.hosts(@build.id)
        deployment = @page.create_or_find_deployment_for(@git_ref_name)

        successful_hosts = sync_to_replicas(hosts,
          GitHub::Routing.dpages_storage_path(@page.id, revision: revision))

        self.class.update_deployment_replicas(deployment, successful_hosts, revision)
        @successful_hosts = successful_hosts
        @page.reload
      end

      def self.current_replicas(page_id)
        ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, page_id: page_id))
          SELECT id, page_id, host FROM pages_replicas WHERE page_id = :page_id
        SQL
      end

      def self.current_revision(page_id)
        ApplicationRecord::Domain::Repositories.connection.select_value(Arel.sql(<<-SQL, page_id: page_id))
          SELECT built_revision FROM pages WHERE id = :page_id
        SQL
      end

      # Atomic update of revision and replica hosts for a deployment
      # For now, support both the old schema, with built_revision stored on pages table,
      # and the new page_deployments table with a ref_name and revision for branch builds.
      def self.update_deployment_replicas(deployment, hosts, revision, update_main_version = false)

        # run all of these queries in a transaction so we don't leave pages in a weird state in case of an error
        ApplicationRecord::Domain::Repositories.transaction do
          if update_main_version || !deployment.branch_build?
            ApplicationRecord::Domain::Repositories.connection.update(Arel.sql(<<-SQL, revision: revision, page_id: deployment.page_id))
              UPDATE pages SET built_revision = :revision WHERE id = :page_id
            SQL
          end

          deployment.update({ revision: revision })
          # pages_replicas may have a NULL pages_deployment_id for the main (not branch) build
          if update_main_version || !deployment.branch_build?
            ApplicationRecord::Domain::Repositories.connection.delete(Arel.sql(<<-SQL, page_id: deployment.page_id, deployment_id: deployment.id))
              DELETE FROM pages_replicas WHERE page_id = :page_id
              AND (pages_deployment_id IS NULL OR pages_deployment_id = :deployment_id)
            SQL
          else
            ApplicationRecord::Domain::Repositories.connection.delete(Arel.sql(<<-SQL, page_id: deployment.page_id, deployment_id: deployment.id))
              DELETE FROM pages_replicas WHERE page_id = :page_id
              AND pages_deployment_id = :deployment_id
            SQL
          end

          rows = hosts.map do |host|
            [deployment.page_id, deployment.id, host, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW]
          end

          ApplicationRecord::Domain::Repositories.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
            INSERT INTO pages_replicas (page_id, pages_deployment_id, host, created_at, updated_at)
            :rows
          SQL
        end
      end

      # TODO - GHE
      # This method was restored from
      # https://github.com/github/github/blob/1c40048624ded6e0184e7a1d4615908d87e9a944/lib/github/pages/builder.rb
      # GitHub::Pages::Builder.update_replicas is called by script/dpages-cluster-import-finalize
      # and used by share/github-backup-utils/ghe-restore-pages-dpages in github/backup-utils.
      # Please fix those to call update_deployment_replicas() instead of update_replicas()
      def self.update_replicas(page_id, replicas, revision)
        ApplicationRecord::Domain::Repositories.transaction do
          ApplicationRecord::Domain::Repositories.connection.update(Arel.sql(<<-SQL, revision: revision, page_id: page_id))
            UPDATE pages SET built_revision = :revision WHERE id = :page_id
          SQL

          ApplicationRecord::Domain::Repositories.connection.delete(Arel.sql(<<-SQL, page_id: page_id))
            DELETE FROM pages_replicas WHERE page_id = :page_id
          SQL

          rows = replicas.map do |replica|
            [page_id, replica, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW]
          end

          ApplicationRecord::Domain::Repositories.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
            INSERT INTO pages_replicas (page_id, host, created_at, updated_at)
            :rows
          SQL
        end
      end

      # Given two lists of voting and non-voting hosts, attempt to sync the
      # compiled site to the hosts. As each page-build runs, keep a list of
      # those for which it completed successfully. This list is returned
      # for use in updating the database. If a non-voting replica fails to
      # sync, it will simply be pruned from the resulting list and no
      # record of it will be made in the database. A subsequent repair job
      # will ensure it exists.
      #
      # hosts - a Hash containing two keys: :voting and :non_voting, each
      # pointing to a separate array of hosts upon which to create
      # replicas.
      # path - path on disk to which the replica should be synced.
      #
      # Returns a list of hostnames which successfully received replicas.
      def sync_to_replicas(hosts, path)
        system_error_msg = "Unable to sync pages directory."
        msg = "#{system_error_msg} Please try again later."
        sync_proc = proc do |host, tries|
          destination = replica_rsync_destination(host, path)
          if GitHub.enterprise?
            GitHub.logger.info("github pages send sync request", {
              "code.namespace" => "github.pages.builder",
              "code.function" => "Pages::Builder.sync_to_replicas",
              "gh.pages.id" => @page.id,
              "gh.repo.nwo" => @page.repository.nwo,
              "gh.catalog_service" => "github/pages"
            }) if GitHub.kube?
            result = @enterprise_build_client.page_sync(
              build_path,
              destination,
              sync_execution_environment
            )
            raise_error(result.err, result.out, msg, system_error_msg, result.status) unless result.status == 0
          else
            sync_script = "page-sync-tar"
            run(
              ["#{pages_jekyll_script_dir}/#{sync_script}", build_path, destination],
              system_error_msg,
              msg,
              env: sync_execution_environment,
              input: "",
              timeout: 10.minutes.to_i,
              tries: tries,
            )
          end
          GitHub.dogstats.increment("pages.page_sync", tags: ["destination:#{host}", "status:success"])
          if feature_enabled?(:pages_build_metrics, @page.repository)
            if @page_size > 0
              GitHub.logger.info("Calculate the stats on build path #{build_path}", {
                "gh.catalog_service" => "github/pages",
                "code.namespace" => "github.pages.builder",
                "code.function" => "Pages::Builder.sync_to_replicas",
                "gh.pages.fileserver.hostname" => host,
                "gh.repo.nwo" => @page.repository.nwo,
                "gh.pages.id" => @page.id,
                "gh.pages.deployment.id" => page_deployment.id,
                "git.ref" => @git_ref_name,
                "gh.pages.size.kb" => @page_size,
                "gh.pages.file.count" => @page_file_count
              })

              GitHub.dogstats.distribution("pages.build_size_kb.dist", @page_size, tags: ["destination:#{host}"])
              GitHub.dogstats.distribution("pages.file_count.dist", @page_file_count, tags: ["destination:#{host}"])
            end
          end
          true
        end

        successful_hosts = Array(hosts[:voting]).flatten.select { |host| sync_proc.call(host, COMMAND_TRIES) }
        if @replicator.write_non_voting_replicas?
          successful_hosts += Array(hosts[:non_voting]).flatten.select do |host|
            begin
              sync_proc.call(host, 0) # don't retry non-voting hosts, let repairs do this
            rescue Error => e
              GitHub.dogstats.increment("pages.page_sync", tags: ["destination:#{host}", "status:error"])
              raise e unless e.to_s.start_with?(system_error_msg)
              # If the sync to a non-voting host fails, do not fail the
              # build. A subsequent run of the repair management operation
              # will ensure a non-voting replica exists.
              Failbot.report(e, app: "pages")
              false
            end
          end
        end

        successful_hosts
      end

      def replica_rsync_destination(host, path)
        if host == GitHub.local_pages_host_name
          path
        else
          "#{host}:#{path}"
        end
      end

      # The path to the scripts in the pages source
      def pages_jekyll_script_dir
        @pages_jekyll_script_dir ||=
          if File.directory?(File.join(GitHub.pages_jekyll_dir, "script"))
            File.join(GitHub.pages_jekyll_dir, "script")
          else
            GitHub.pages_jekyll_dir
          end
      end

      # Determine whether the pages build environment is available.
      #
      # Returns true if the build commands are available, false otherwise.
      # Side-effect: Populates @page_build_usage and @page_build_params
      #              if required by the page to check if build_compatible.
      def build_environment_available?
        return @build_environment_available if defined?(@build_environment_available)
        return @enterprise_build_client.page_build_available? if GitHub.enterprise?
        dir = pages_jekyll_script_dir
        @build_environment_available ||= (
          File.executable?("#{dir}/page-build") &&
          File.executable?("#{dir}/page-sync-tar") &&
          (!@page.subdir_source? ||
            ((@page_build_usage = IO.readlines("#{dir}/page-build")[1]) &&
            (@page_build_params = @page_build_usage.count("<"))))
        )
      end

      # Determine if the deployed page-build is compatible with this page
      # page.source requires extra parameter introduced in github/pages/pull/922
      def build_compatible?

        # the validation should be gate by build api now, no need to have an extra check on GHES environment.
        return true if GitHub.enterprise?
        !@page.subdir_source? || @page_build_params > 3
      end

      # Determine if this is a github.com production environment. This determines
      # whether command isolation, librato config, and remote sync'ing needs to
      # happen.
      def production_environment?
        Rails.env.production? || Rails.env.staging?
      end

      # The path to build the pages site at on the current machine. Files in this
      # directory are output from jekyll.
      def build_path
        @build_path ||= "#{build_user_path}/#{SecureRandom.uuid}"
      end

      # List of non-underscored top level directories under the build root.
      # Since these dirs explicitly appear, they are allowed to override
      # gh-pages subdirs.
      def build_path_directories
        Array(Dir["#{build_path}/*"]).
          map     { |f| File.basename(f) }.
          reject  { |f| f[0] == "_" || !File.directory?("#{build_path}/#{f}") }
      end

      # The process environment used to executed page-build command.
      def build_execution_environment
        basic_execution_environment.merge(command_execution_environment)
      end

      # Ditto for page-sync command.
      def sync_execution_environment
        environment = build_execution_environment
        environment.delete("RSYNC")
        environment
      end

      # Environment variables used for all page-* commands executed to build the
      # pages site.
      def basic_execution_environment
        {
          "GEM_HOME"          => nil,
          "GEM_PATH"          => nil,
          "RUBYLIB"           => nil,
          "TMPDIR"            => @build_dir,
          "BUNDLE_GEMFILE"    => nil,
          "BUNDLE_APP_CONFIG" => nil,
          "RBENV_VERSION"     => nil,
          "PAGES_STATS_HOSTS" => GitHub.stats_allowlist ? "" : (GitHub.stats_hosts || []).join(","),
        }
      end

      # Environment variables that override commands needed to build the site.
      # The page build and sync commands use these so that commands may be
      # locked down to a user or other policy can be enforced.
      def command_execution_environment

        if GitHub.enterprise?
          env = { "PAGES_ENV" => "enterprise", "RBENV_VERSION" => ENV["RBENV_VERSION"] }
        elsif production_environment?
          env = { "PAGES_ENV" => "dotcom" }
        else
          env = { "PAGES_ENV" => "development" }
        end

        # Pass the pushers ID, since a user cant be determined from a integration token
        env["PUSHER_ID"] = @pusher.id.to_s

        # Use a filebased Failbot in Enterprise and in development for pages,
        # much like we do for github/github
        if Rails.env.development? || (GitHub.enterprise? && !Rails.env.test?)
          env["FAILBOT_BACKEND"] = "file"
          env["FAILBOT_BACKEND_FILE_PATH"] = GitHub.pages_failbot_backend_file_path
        end

        # In development, pass request token and nwo since they aren't passed in the clone_url
        if Rails.env.development?
          env["REQUEST_TOKEN"]  = should_use_apps? ? pages_github_app_token : oauth_token
          env["REPOSITORY_NWO"] = @page.repository.nwo
        end

        # Add flipper features
        env["PAGES_FEATURES_STATUSES"]   = pages_statuses_enabled?(@page.repository) ? "enabled" : ""
        env["PAGES_FEATURES_CHECKS_API"] = pages_features_checks_api_enabled? ? "enabled" : ""
        env["PAGES_FEATURES_GITHUB_APP"] = should_use_apps? ? "enabled" : ""
        env["PAGES_BETA_IMAGE"]          = pages_beta_image?(@page.repository) ? "enabled" : ""
        env["PAGES_BRANCH_BUILD"]        = page_deployment.branch_build? ? "true" : "false"

        # Pass the configured pages site size limit in the environment.
        env["PAGES_SIZE_LIMIT"]    = GitHub.pages_site_size_limit.to_s
        env["PAGES_HOSTNAME"]      = GitHub.pages_host_name_v2
        env["GITHUB_HOSTNAME"]     = GitHub.host_name
        env["ASSET_HOST_URL"]      = GitHub.asset_host_url
        env["SUBDOMAIN_ISOLATION"] = GitHub.subdomain_isolation?.to_s
        env["SSL"]                 = GitHub.ssl?.to_s
        env["API_URL"]             = GitHub.api_url
        env["HELP_URL"]            = GitHub.help_url
        env["EARLY_ACCESS"]        = @page.repository.preview_features?.to_s
        env["GITHUB_STAFF"]        = @pusher.preview_features?.to_s
        env["OAUTH_BUILD"]         = Rails.env.production?.to_s
        env["PAGE_BUILD_ID"]       = page_build_id
        env["PAGE_PREVIEW_URL"]    = page_deployment.preview_url
        env["NETWORK_PROXY_URL"]   = network_proxy_url
        env["NO_PROXY"]            = no_proxy_allowlist if GitHub.enterprise?

        env
      end

      # Internal: A comma-separated list of destination hosts exempt from
      # proxying when NETWORK_PROXY_URL is configured.
      #
      # Returns a string of comma-separated list of hostnames and IP addresses
      def no_proxy_allowlist
        local_traffic = "localhost,127.0.0.1,::1,#{GitHub.host_name}"
        allowed_hostnames = local_traffic
        allowed_hostnames << ",#{GitHub.no_proxy_config}" unless GitHub.no_proxy_config.nil?
        allowed_hostnames
      end

      def network_proxy_url
        if GitHub.enterprise?
          GitHub.http_proxy_config
        else
          GitHub.external_communication_proxy_host
        end
      end

      # The containing directory used to perform page builds.
      def build_user_path
        @build_user_path ||= [
          @build_dir,
          "pagebuilds",
          repository.owner.to_s.downcase,
        ].join("/")
      end

      # The underlying Repository record for the current page.
      def repository
        @page.repository
      end

      # The Page::Deployment for this build
      def page_deployment
        @page_deployment ||= @page.create_or_find_deployment_for(@git_ref_name)
      end

      def raise_error(err, out, msg, system_error_msg, status)
        error = sanitized_error(err) || msg
        stdout = filter_tokens(out)
        stderr = filter_tokens(err)

        # Scrub fastly api key from logs
        find = /GH_FASTLY_APIKEY=[\S]+/
        replace = "GH_FASTLY_APIKEY=[FASTLY_KEY]"
        stdout = stdout.gsub(find, replace)
        stderr = stderr.gsub(find, replace)

        Failbot.push(
          :catalog_service => "github/pages",
          "code.function" => "builder.raise_error",
          "code.namespace" => "github.pages",
          "gh.pages.cleanup_build_and_sync.filtered_stdout" => stdout,
          "gh.pages.cleanup_build_and_sync.filtered_stderr" => stderr,
          "gh.pages.status" => status,
          "gh.pages.sanitized_error" => error,
          "gh.pages.cleanup_build_and_sync.filtered_warning" => warning(err),
        )
        if authentication_error?(err)
          raise AuthError, error
        # Segment system errors we cause from user-caused errors
        elsif error && error.start_with?(system_error_msg)
          raise Error, error
        else
          raise UserError, error
        end
      end

      # Run the passed in command (with process options) and throw an
      # appropriate exception if the process does not execute successfully.
      #
      # command - The command to execute.
      # system_error_msg - The error message this command returns by default.
      #   This is used to differentiate a UserError from an Error.
      # msg - The error message to use if the error is due to a UserError.
      # options - A Hash of options passed to Progeny::Command
      #
      # Returns a Progeny::Command if the process executes successfully and
      # throws an appropriate exception otherwise.
      def run(command, system_error_msg = nil, msg = nil, options = {})
        msg ||= system_error_msg

        sanitized_command = sanitize_command(command)

        Failbot.push(
          :catalog_service => "github/pages",
          "code.function" => "builder.run",
          "code.namespace" => "github.pages",
          "gh.repo.id" => repository.id,
          "gh.user.id" => repository.owner.id,
          "gh.pages.id" => @page.id.inspect,
          "gh.pages.build_command" => sanitized_command.inspect,
          "gh.pages.build_options" => options.inspect,
          "gh.pages.app.installation.present" => pages_github_app_installation.present?
        )

        env     = options.delete(:env) || {}
        options = options.merge(pgroup_kill: true)
        tries   = options.delete(:tries) || (production_environment? ? COMMAND_TRIES : 0)
        log({ fn: "page-builder-run", command: command.join(" ") }.merge(env))

        process = Progeny::Command.new(env, *(command + [options]))
        (1...tries).each do |_try|
          break if process.status.success?
          sleep COMMAND_RETRIES_SLEEP
          process = Progeny::Command.new(env, *(command + [options]))
        end

        if !process.status.success?
          raise_error(process.err, process.out, msg, system_error_msg, process.status.exitstatus.inspect)
        else
          process
        end
      end

      # Builds the page and retries up to BUILD_TRIES times if it fails due to
      # an authentication failure. Pages explicitly creates an OAuth token, so
      # an authentication error should only happen if there was a race between
      # when the OAuth token was generated and when the current value propagates
      # to the DB replicas. Once we add support for MySQL GTIDs we may
      # reconsider revising the Pages build logic to wait for the replicas to
      # update before using the OAuth token.
      def page_build
        tries ||= BUILD_TRIES
        replicate_oauth_token! # skipped if using GitHub Apps

        timing_key = Page.build_in_docker? ? "page-build-docker" : "page-build"
        system_error_msg = "Page build failed."
        msg = "Unable to build page. Please try again later."
        log_build_step(timing_key) do
          if GitHub.enterprise?
            GitHub.logger.info("github pages send build request", {
              "gh.pages.id" => @page.id,
              "gh.repo.nwo" => @page.repository.nwo,
              "gh.catalog_service" => "github/pages"
            }) if GitHub.kube?
            result = @enterprise_build_client.page_build(
              clone_url,
              @git_ref_name,
              @page.source_dir,
              build_path,
              build_execution_environment
            )
            raise_error(result.err, result.out, msg, system_error_msg, result.status) unless result.status == 0
            return result
          else
            run(
              @page.subdir_source? ? ["#{pages_jekyll_script_dir}/page-build", clone_url, @git_ref_name, @page.source_dir, build_path] : ["#{pages_jekyll_script_dir}/page-build", clone_url, @git_ref_name, build_path],
              system_error_msg,
              msg,
              env: build_execution_environment,
              timeout: 11.minutes.to_i,
              tries: 1,
            )
          end
        end
      rescue AuthError
        tries -= 1
        if tries > 0
          # Give the DB replicas time to update with the current OAuth token
          # value.
          sleep(BUILD_SLEEP_TIME)
          retry
        else
          raise
        end
      end

      def page_build_id
        @build && "page_build:#{@build.id}"
      end

      # Returns whether the process failure was due to an authentication error.
      def authentication_error?(err_msg)
        err_msg.index(AUTH_ERROR_MESSAGE)
      end

      # Returns the sanitized error as passed from PagesJekyll
      def sanitized_error(output)
        output[/^\+ \e\[31mPagesJekyll Sanitized Error: (.+)\e\[0m$/, 1]
      end

      def filter_tokens(output)
        return if output.nil?
        # if a token is nil, standard gsub will match every character
        if oauth_token.present?
          output = output.gsub(oauth_token.to_s, "[OAUTH TOKEN]")
        end
        if pages_github_app_token.present?
          output = output.gsub(pages_github_app_token.to_s, "[X-ACCESS-TOKEN]")
        end

        output
      end

      def warning(output)
        match = output.match(/^\+ \e\[33mPagesJekyll Warning: (.+?)\e\[0m$/m)
        match[1] if match
      end

      def step_times
        @step_times ||= {}
      end

      def log_build_step(fn)
        start_time = Time.now
        yield
      ensure
        elapsed = (Time.now - start_time) * 1_000
        step_times["#{fn}-time"] = elapsed
        GitHub.dogstats.distribution "pages.#{fn}.dist", elapsed
      end

      def log(data)
        data = data.dup
        data.each_key do |key|
          data[key] = filter_tokens(data[key].to_s)
        end
        GitHub.logger.info(base_log_data.merge(data))
      end

      def base_log_data
        @base_log_data ||= {
          "gh.pages.build.id" => page_build_id,
          "git.ref" => @git_ref_name.inspect,
          "gh.repo.nwo" => repository.name_with_owner,
        }.freeze
      end

      # Report a failed build check run or status.
      def report_failed_build_to_user
        if should_use_apps?
          report_failed_build_check(repo: repository, git_ref_name: @git_ref_name, actor: @pusher)
        elsif pages_statuses_enabled?(repository)
          report_failed_build_status(repo: repository, git_ref_name: @git_ref_name, pages_oauth_access: pages_oauth_access)
        end
      end

      # Report a failed build status for the given repository, git ref, and pages OAuth access.
      def report_failed_build_status(repo:, git_ref_name:, pages_oauth_access:)
        Statuses::Service.create_status(
          repo: repo,
          data: {
            state: "failure",
            description: BUILD_TIMEOUT_ERROR,
            context: "github/pages",
            sha: repo.refs.find(git_ref_name).target_oid,
            oauth_application_id: pages_oauth_access.application.id,
          },
          user: Organization.find_by_login("github"),
        )
      end

      # Report a failed build check run for the given repository, git ref, and actor.
      def report_failed_build_check(repo:, git_ref_name:, actor:)
        check_suite = Checks::Service.find_or_create_check_suite(
          github_app_id: GitHub.pages_github_app.id,
          head_sha: repo.refs.find(git_ref_name).target_oid,
          repo: repo,
        )
        check_suite.check_runs.create!(
          creator_id: actor.id,
          name: GitHub.pages_check_run_name,
          status: :completed,
          conclusion: :timed_out,
          started_at: Time.now.utc,
          completed_at: Time.now.utc,
          details_url: GitHub.pages_help_url,
          title: CHECK_FAILURE_TITLE,
          summary: BUILD_TIMEOUT_ERROR,
          repository: repo,
        )
      rescue ActiveRecord::RecordInvalid => error
        Failbot.report(error, {
          :catalog_service => "github/pages",
          "code.function" => "builder.report_failed_build_check",
          "code.namespace" => "github.pages",
        })
        false
      end
    end
  end
end
