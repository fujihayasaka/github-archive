# typed: true
# frozen_string_literal: true

module GitAuth
  # The target of the git operation.
  # This can be a repository, a wiki, or a gist.
  # If the target of the operation is a wiki we keep track
  # of the fact that the actual operation is the wiki, but
  # we use the parent repo of the wiki as the GitAuth::Target,
  # because we need to ask about all the permissions stuff, and
  # that is implemented on the Repository, not the wiki.
  class Target
    REPO_PATH = /\A\/?(([A-Za-z0-9][A-Za-z0-9@._-]*\/[\w.-]+)\.git)\z/
    V1_GIST_PATH = /\A(\d+)\.git\z/
    V2_GIST_PATH = /\A([a-f0-9]{20})\.git\z/
    V3_GIST_PATH = /\A([a-f0-9]{32})\.git\z/

    attr_reader :path
    def initialize(path)
      @path = path
      @owner_name_from_path, @repo_name_from_path = user_repo_for(path)

      if @repo_name_from_path && @repo_name_from_path.end_with?(".wiki")
        if gist?
          # This is neither a wiki nor a gist, and it doesn't point to anything.
          @broken = true
        else
          @wiki = true
          @repo_name_from_path.chomp!(".wiki")
        end
      end

      @name_with_owner = "#{standardize_owner_name(@owner_name_from_path)}/#{@repo_name_from_path}"
    end

    # If the repository `redirected?` is true, this function can be used to get the repo owner and name from the `Target` path.
    def redirected_from
      "#{User.to_display_login(@owner_name_from_path)}/#{@repo_name_from_path}"
    end

    # True when the user has passed us impossible data.
    def broken?
      @broken
    end

    def valid?
      @owner_name_from_path && @repo_name_from_path
    end

    # True when the repository path matches the form <name>.wiki.git.
    # The :repo_name_from_path attribute of the target does not include the '.wiki' suffix.
    def wiki?
      @wiki
    end

    def gist?
      @owner_name_from_path == "gist" && !broken?
    end

    def normal_repo?
      !wiki? && !gist?
    end

    def type
      if wiki?
        "wiki"
      elsif gist?
        "gist"
      else
        "repository"
      end
    end

    # Check if the repository requested has been redirected.
    # The redirected to repository must exist and not be in a deleted state.
    def redirected?
      return false if gist? || broken?

      repository&.name_with_owner != name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner
    end

    # Repository-like object corresponding to the path. The located repository
    # may have a different canonical path than what was requested based on
    # redirect entries. Requests for repository paths that have been redirected
    # are served as if they were made on the redirected repository.
    #
    # Returns a Repository or Gist based on the path, or nil when no matching
    # repository can be found.
    def repository
      return @repository if defined?(@repository)

      if gist?
        @repository = GitAuth::Gist.with_name(@repo_name_from_path)
      end

      @repository ||= Repositories.domain.by_qualified_name(name_with_owner) # rubocop:disable GitHub/DoNotAllowNameWithOwner
      @repository ||= redirected_repository(name_with_owner) # rubocop:disable GitHub/DoNotAllowNameWithOwner

      @repository
    end

    def repository_spec
      if wiki?
        repository&.unsullied_wiki&.repository_spec
      else
        repository&.repository_spec
      end
    end

    def postrx_hook_url
      repository.post_receive_hook_url(wiki?)
    end

    def host
      gist? ? repository.route : repository.host
    end

    def full_path
      if gist?
        repository.shard_path
      elsif wiki?
        repository.unsullied_wiki.shard_path
      else
        repository.shard_path
      end
    end

    def exist?
      if wiki?
        repository.unsullied_wiki.exist?
      else
        repository.exists_on_disk?
      end
    end

    def routes(shard, protocol, action)
      # See https://github.com/github/github/pull/71876
      # for a great write-up about selecting dgit routes
      # depending on various conditions.
      dgit_routes = if shard =~ /\.wiki\.git$/
        # wikis that haven't been initialized on disk yet
        # won't be able to call dgit_wiki_*_routes, but we
        # still have to return routes here -- the routes
        # where the wiki would be if someone created one.
        if !repository.unsullied_wiki.exist?
          override = repository.dgit_all_routes
          override = override.map do |route|
            r = route.dup
            r.path = r.path.sub(/\.git$/, ".wiki.git")
            r
          end
        end
        if action == "write"
          override ? override.reject(&:cache_server?).sort : repository.dgit_wiki_write_routes
        else
          override ? override : repository.dgit_wiki_read_routes(cache_servers_ok: true)
        end
      else
        if action == "write"
          repository.dgit_write_routes
        else
          repository.dgit_read_routes(cache_servers_ok: true)
        end
      end
      if protocol == "svn" && action == "write"
        dgit_routes = dgit_routes.sort_by { |route| [route.quiescing ? 1 : 0, -route.read_weight.to_i, Digest::SHA256.hexdigest(route.original_host + repository.dgit_spec)] } # rubocop:disable GitHub/DoNotAllowNameWithOwner creates a hash from the nwo and therefore is not display related
      end

      dgit_routes.map do |route|
        [route.resolved_host, route.path].concat(route.ignore_recv_errors? ? ["noerror"] : [])
      end
    end

    private

    attr_reader :name_with_owner

    def user_repo_for(path)
      case path
      when REPO_PATH
        $2.split("/", 2)
      when V3_GIST_PATH, V2_GIST_PATH, V1_GIST_PATH
        ["gist", $1]
      end
    end

    def redirected_repository(name_with_owner)
      return nil if name_with_owner.to_s.empty?

      id = ApplicationRecord::Domain::Repositories.connection.select_value(Arel.sql(<<-SQL, repository_name: name_with_owner))
        SELECT repository_id
        FROM repository_redirects
        WHERE repository_name=:repository_name
        ORDER BY created_at DESC
        LIMIT 1
      SQL
      return if id.nil?

      Repository.find_by(id: id, active: true)
    end

    # takes the given "targetted" owner name
    # and appends the tenant suffix if in multi-tenant environment and not already suffixed
    def standardize_owner_name(owner_name_from_path)
      return owner_name_from_path unless owner_name_from_path.present?
      return owner_name_from_path unless User.scope_to_current_tenant?
      return owner_name_from_path if User.unique_tenant_login?(owner_name_from_path)
      User.standardize_login(owner_name_from_path, suffix: GitHub::CurrentTenant.get.shortcode)
    end
  end
end
