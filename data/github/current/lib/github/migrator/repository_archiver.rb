# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class RepositoryArchiver < BaseArchiver
      include RepoHelpers
      include GitHub::Rsync

      def save(repo)
        owner_name = repo.owner.login
        clone_path = File.join(migration_path, "repositories", owner_name, "#{repo.name}.git")

        # Make a bare clone of the repository.
        archive_repo repo: repo, to: clone_path

        # Check if wiki is enabled for repository.
        if repo.has_wiki?
          wiki = repo.unsullied_wiki

          # Check if wiki has been created.
          if wiki.exist?
            clone_path = File.join(migration_path, "repositories", owner_name, "#{repo.name}.wiki.git")

            # Make a bare clone of the wiki.
            archive_repo repo: wiki, to: clone_path
          end
        end
      end

      def archive_repo(repo:, to:)
        to = to.to_s

        # Kill the last attempt to export.
        FileUtils.rm_rf(to) if Dir.exist?(to)

        # Start with a normal git clone, so that we get objects stored in a network repo, if it exists.
        command = ["git", "clone", "--mirror", "--no-local", repo.internal_remote_url, to]
        child = Progeny::Command.new(*command)
        if !child.success?
          raise ChildProcessError, "#{command.join(" ")}: #{child.status.inspect}\n\nSTDOUT:\n#{child.out}\nSTDERR:\n#{child.err}"
        end

        rsync_opts = {}
        rsync_opts[:from] = local_repo?(repo) ? repo.shard_path : repo.internal_remote_url
        rsync_opts[:to] = to

        if GitHub.enterprise?
          # Preserve everything else in the repo, too.
          # * Skip "HEAD", "objects/", "refs/" and "packed-refs" since it's redundant with the clone.
          # * Skip "hooks/" to avoid an rsync conflict with what's in the mirrored repository.
          # e.g. https://gist.ghe.io/spraints/c7699a22f47ef979bcb9
          rsync_opts[:exclude] = %w(/HEAD /objects /refs /packed-refs /hooks)
        else
          # Preserve just the SVN data.
          # e.g. https://gist.ghe.io/spraints/53ea9d2022ed9e2c1700
          rsync_opts[:filters] = ["+ /svn**", "- *"]
        end

        rsync(rsync_opts)
      rescue ChildProcessError, ::GitHub::Rsync::ChildProcessError => e
        raise GitHub::Migrator::ExportFailure.new("There was an issue archiving repository data for repository #{repo.name}.")
      end
    end
  end
end
