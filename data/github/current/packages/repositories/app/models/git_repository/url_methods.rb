# typed: false
# frozen_string_literal: true

# Defines Git URL methods for Repository and GitHub::Unsullied::Wiki objects.
#
# Recipients should define these methods?
#
#   #short_git_path (Repository/Gist#name_with_owner)
#   #pushable_by?(user)
#   #public?
#   #route
#   #shard_path
#
module GitRepository::UrlMethods
  # Public: Builds an object to select the preferred protocol for accessing
  # this repository.
  #
  # user - Optional User to get preferences from.
  #
  #   selector = repo.protocol_selector
  #   selector.push_protocol # http (default)
  #
  #   user.protocols = {'push' => 'ssh'}
  #   selector = repo.protocol_selector(user)
  #   selector.push_protocol # ssh
  #
  # Returns a new GitHub::RepositoryProtocolSelector.
  def protocol_selector(user = nil)
    GitHub::RepositoryProtocolSelector.new(self, user)
  end

  # Builds the gitweb clone url for a git repository.
  #
  # Returns a String uri.
  def gitweb_url
    "git://#{clone_host_name}/#{short_git_path}.git"
  end

  # Builds the API specific gitweb clone url for a git repository.
  #
  # Returns a String uri.
  def gitweb_url_for_api(serialize_login: :default)
    "git://#{clone_host_name}/#{name_with_owner_for_api(use: serialize_login)}.git"
  end

  # Builds the local filesystem path to a git repository.
  #
  # Returns a String uri.
  def local_url
    "file://#{shard_path}"
  end

  # Builds an SSH url to this git repository.  This url is for external users,
  # not for internal use (see internal_ssh_url)
  #
  # Returns a String url
  def ssh_url
    return @ssh_url if defined?(@ssh_url)

    git_path = case self
    when Repository
      name_with_display_owner
    else
      short_git_path
    end

    @ssh_url = if Rails.env.development?
      "ssh://#{ssh_login_for_url}@localhost:3035/#{git_path}.git"
    else
      "#{ssh_login_for_url}@#{clone_host_name}:#{git_path}.git"
    end
  end

  # Builds an API specific SSH url to this git repository.  This url is for external users,
  # not for internal use (see internal_ssh_url)
  #
  # Returns a String url
  def ssh_url_for_api(serialize_login: :default)

    return @ssh_url_for_api if defined?(@ssh_url_for_api)

    @ssh_url_for_api = if Rails.env.development?
      "ssh://#{ssh_login_for_url}@localhost:3035/#{name_with_owner_for_api(use: serialize_login)}.git"
    else
      "#{ssh_login_for_url}@#{clone_host_name}:#{name_with_owner_for_api(use: serialize_login)}.git"
    end
  end

  def ssh_login_for_url
    if GitHub.multi_tenant_enterprise?
      tenant_slug = GitHub::CurrentTenant.get&.slug
      if try(:usable_ssh_certificate_authorities)&.any?
        "#{tenant_slug}_#{organization_id}"
      else
        tenant_slug
      end
    elsif try(:usable_ssh_certificate_authorities)&.any?
      "org-#{organization_id}"
    else
      "git"
    end
  end

  # Builds the URL used to push/fetch from this repository when on the same
  # machine or inside the production network. This should be used any time
  # you need to access a repository over git protocols for internal access
  # (e.g., forking, cloning, pushing with --mirror for import, etc).
  #
  # This should work in all environments as well as with FI.
  #
  # Return a String URL.
  def internal_remote_url
    dgit_read_routes.first.remote_url
  end

  # The URL used by network repositories to fetch this repository.
  #
  # Returns a path to the repository relative to the network repository if the
  #   repository is network routed, or the internal_remote_url when the
  #   repository is user routed.
  def network_fetch_url
    "../#{id}.git"
  end

  # What host name are we using for cloning?
  def clone_host_name
    if GitHub.multi_tenant_enterprise?
      GitHub.host_name_with_tenant
    else
      GitHub.host_name
    end
  end

  # Builds a smart HTTP url to a git repository.
  #
  # Returns a String uri.
  def http_url
    proto = GitHub.ssl? ? "https" : "http"

    git_path = case self
    when Repository
      name_with_display_owner
    else
      short_git_path
    end

    "#{proto}://#{clone_host_name}/#{git_path}.git"
  end

  # Builds a API specific smart HTTP url to a git repository.
  #
  # Returns a String uri.
  def http_url_for_api(serialize_login: :default)
    proto = GitHub.ssl? ? "https" : "http"
    "#{proto}://#{clone_host_name}/#{name_with_owner_for_api(use: serialize_login)}.git"
  end

  # Builds a Subversion url to a git repository. Slummin'
  #
  # Returns a String uri.
  def svn_url
    "#{GitHub.subversion_url}/#{short_git_path}"
  end
  alias_method :subversion_url, :svn_url

  # Builds a API specific Subversion url to a git repository. Slummin'
  #
  # Returns a String uri.
  def svn_url_for_api(serialize_login: :default)
    "#{GitHub.subversion_url}/#{name_with_owner_for_api(use: serialize_login)}"
  end

  # Returns the default push url for this repository.  This protocol may vary
  # depending on the environment (dev, Enterprise, etc)
  #
  # Returns a String uri.
  if Rails.env.development?
    alias push_url local_url
  else
    alias push_url http_url
  end

  # Returns the default clone url for this repository.  This protocol may vary
  # depending on the environment (dev, Enterprise, etc)
  #
  # Returns a String uri.
  alias clone_url http_url
  alias clone_url_for_api http_url_for_api
end
