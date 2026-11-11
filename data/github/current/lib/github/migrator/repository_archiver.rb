# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class RepositoryArchiver < BaseArchiver
      include RepoHelpers
      include GitHub::Rsync

      CODEPATH_MIGRATOR_REPOSITORY_ARCHIVER = "migrator/repository_archiver".freeze
      ENTRYPOINT_MIGRATOR_SITE_SCOPED_TOKEN = :rest_api_migrator_repository_archiver_site_scoped_token

      def save(repo)
        owner_name = repo.owner&.display_login || repo.owner_display_login
        clone_path = File.join(migration_path, "repositories", owner_name, "#{repo.name}.git")

        # Make a bare clone of the repository.
        archive_repo source: repo, to: clone_path

        # Check if wiki is enabled for repository.
        if repo.has_wiki?
          wiki = repo.unsullied_wiki

          # Check if wiki has been created.
          if wiki.exist?
            clone_path = File.join(migration_path, "repositories", owner_name, "#{repo.name}.wiki.git")

            # Make a bare clone of the wiki.
            archive_repo source: wiki, to: clone_path
          end
        end
      end

      def archive_repo(source:, to:)
        to = to.to_s

        # Kill the last attempt to export.
        FileUtils.rm_rf(to) if Dir.exist?(to)
        flag_actor = flag_actor_for(source)
        repo_actor  = repo_actor_for(source)

        command = if FeatureFlag.vexi.enabled?(:migrator_http_clone_for_export, repo_actor, default: false)
          ["git", "clone", "--mirror", "--no-local", clone_url_for_export(source), to]
        else
          # Start with a normal git clone, so that we get objects stored in a network repo, if it exists.
          ["git", "clone", "--mirror", "--no-local", source.internal_remote_url, to]
        end

        child = Progeny::Command.new(*command)

        unless child.success?
          safe_command = sanitized_command_for_logging(command)
          safe_stdout = sanitized_output_for_logging(child.out)
          safe_stderr = sanitized_output_for_logging(child.err)

          raise ChildProcessError, "#{safe_command.join(" ")}: #{child.status.inspect}\n\nSTDOUT:\n#{safe_stdout}\nSTDERR:\n#{safe_stderr}"
        end

        true
      rescue GitHub::Migrator::ExportFailure, ChildProcessError, ::GitHub::Rsync::ChildProcessError => e
        raise GitHub::Migrator::ExportFailure.new(
          "There was an issue archiving repository data for repository #{source_name_for_error(source)}: #{e.message}"
        )
      rescue StandardError => e
        raise GitHub::Migrator::ExportFailure.new(
          "Unexpected error while archiving repository #{source_name_for_error(source)}: #{e.message}"
        )
      end

      private

      def expected_export_clone_path(source, repo)
        if wiki_source?(source, repo)
          "#{repo.name_with_display_owner}.wiki.git"
        else
          export_clone_path_from(repo)
        end
      end

      def wiki_source?(source, repo)
        return false if source == repo

        source_path = export_clone_path_from(source)
        repo_wiki_path = "#{repo.name_with_display_owner}.wiki.git"

        source.respond_to?(:repository) &&
          source.repository == repo &&
          source_path == repo_wiki_path
      end

      def source_name_for_error(source)
        if source.respond_to?(:name_with_display_owner) && source.name_with_display_owner.present?
          source.name_with_display_owner
        elsif source.respond_to?(:short_git_path) && source.short_git_path.present?
          source.short_git_path
        elsif source.respond_to?(:name) && source.name.present?
          source.name
        else
          source.class.name
        end
      end

      def repo_actor_for(source)
        return source.repository if source.respond_to?(:repository) && source.repository
        source
      end

      def flag_actor_for(source)
        return source.owner || source if source.respond_to?(:owner)
        return source.repository.owner || source.repository if source.respond_to?(:repository) && source.repository.respond_to?(:owner)

        source
      end

      def clone_url_for_export(source)
        repo = source.respond_to?(:repository) ? source.repository : source
        validate_export_clone_target!(source, repo)
        token = export_token_for(repo)
        base_url = base_url_for_export(source, repo)

        inject_token_into_url(base_url, token)
      end

      def validate_export_clone_target!(source, repo)
        source_host = export_clone_host_from(source)
        repo_host = export_clone_host_from(repo)

        if source_host != repo_host
          raise GitHub::Migrator::ExportFailure,
            "Resolved clone host does not match canonical repository host for #{repo.name_with_display_owner}."
        end

        source_path = export_clone_path_from(source)
        expected_path = expected_export_clone_path(source, repo)

        if source_path != expected_path
          raise GitHub::Migrator::ExportFailure,
            "Resolved clone path does not match canonical repository path for #{repo.name_with_display_owner}."
        end
      end

      def base_url_for_export(source, repo)
        host = export_clone_host(source, repo)
        path = export_clone_path(source, repo)

        "https://#{host}/#{path}"
      end

      def export_clone_host(source, repo)
        export_clone_host_from(source) || export_clone_host_from(repo) ||
          raise(GitHub::Migrator::ExportFailure, "Could not determine clone host for export.")
      end

      def export_clone_host_from(record)
        return unless record.respond_to?(:http_url) && record.http_url.present?

        URI.parse(record.http_url).host
      end

      def export_clone_path(source, repo)
        export_clone_path_from(source) || export_clone_path_from(repo) ||
          raise(GitHub::Migrator::ExportFailure, "Could not determine clone path for export.")
      end

      def export_clone_path_from(record)
        raw_path =
          if record.respond_to?(:short_git_path) && record.short_git_path.present?
            record.short_git_path
          elsif record.respond_to?(:name_with_display_owner) && record.name_with_display_owner.present?
            record.name_with_display_owner
          end

        return unless raw_path.present?

        raw_path.end_with?(".git") ? raw_path : "#{raw_path}.git"
      end

      def inject_token_into_url(url, token)
        uri = URI.parse(url)

        unless uri.scheme == "https"
          raise GitHub::Migrator::ExportFailure,
            "Refusing to inject credentials into a non-HTTPS clone URL: #{uri.scheme}://#{uri.host}"
        end

        uri.user = "x-access-token"
        uri.password = token
        uri.to_s
      end

      def export_token_for(repo)
        app = Apps::Privileged.integration(:migrator)
        raise GitHub::Migrator::ExportFailure, "Migrator app is not configured." unless app

        repo_owner = repo.owner
        installation = site_scoped_installation_for_global_app(app, repo, repo_owner)

        unless installation
          raise GitHub::Migrator::ExportFailure,
            "Could not find migrator app installation for #{repo.name_with_display_owner}."
        end

        response = ActiveRecord::Base.connected_to(role: :writing) do
          actors = [app, repo_owner, repo].compact

          installation.generate_token(
            code_path: CODEPATH_MIGRATOR_REPOSITORY_ARCHIVER,
            redis_with_mysql_fallback: ServerToServerTokens.domain.redis_with_mysql_fallback?(actors),
          )
        end

        case response
        when GH::Result::Ok
          response.value.token_value
        when GH::Result::Error
          raise GitHub::Migrator::ExportFailure, "Unable to generate migrator app token: #{response.message}"
        else
          raise GitHub::Migrator::ExportFailure, "Unexpected response when generating migrator app token."
        end
      end

      def site_scoped_installation_for_global_app(app, repo, repo_owner)
        return unless repo_owner.is_a?(Business) || repo_owner.is_a?(User)

        permissions = Repository::Resources.filter(app.default_permissions)
        return if permissions.none?

        entry_point = Permissions::Service::EntryPoint.build(
          ENTRYPOINT_MIGRATOR_SITE_SCOPED_TOKEN,
          target: repo_owner,
          actor_owner: app,
        )

        result = ActiveRecord::Base.connected_to(role: :writing) do
          SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            app,
            repo_owner,
            repositories: [repo],
            permissions: permissions,
            entry_point: entry_point,
          )
        end

        if result.failed?
          raise GitHub::Migrator::ExportFailure,
            "Could not create site scoped installation for #{repo.name_with_display_owner}: #{result.error}"
        end

        result.installation
      end

      def sanitized_command_for_logging(command)
        command.map { |part| sanitize_token_for_logging(part) }
      end

      def sanitized_output_for_logging(output)
        sanitize_token_for_logging(output)
      end

      def sanitize_token_for_logging(value)
        value.to_s.gsub(%r{x-access-token:[^@]+@}, "x-access-token:[REDACTED]@")
      end
    end
  end
end
