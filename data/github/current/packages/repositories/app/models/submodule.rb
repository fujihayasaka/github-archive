# typed: true
# frozen_string_literal: true

# This class takes a hash describing a submodule using url, name, path, and
# branch and tells the caller if it represents a repo, gist, or wiki.
#
# It also parses out the respective parts of the URL to make them accessible.
class Submodule
  attr_reader :submodule_data, :user, :repo, :gist, :name, :path, :url, :branch,
    :superproject_repository, :superproject_commit_oid

  # superproject_repository - The repository this submodule is hosted in
  # superproject_commit_oid - The commit oid for the superproject that this
  #                           submodule definition is valid as of.  Put
  #                           another way, This is the commit oid that
  #                           contains the `.gitmodules` file that this
  #                           instance was parsed from.
  # submodule_data          - A hash with "name", "path", "url", and "branch"
  #                           being the only valid keys.
  def initialize(superproject_repository:, superproject_commit_oid:, submodule_data:)
    @superproject_repository = superproject_repository
    @superproject_commit_oid = superproject_commit_oid
    @name = submodule_data["name"]
    @path = submodule_data["path"]
    @url = submodule_data["url"]
    @branch = submodule_data["branch"]
    parse_github_url
  end

  # Returns the commit oid of the subproject this repo refers to as of this
  # superproject revision.  This will be an oid that does not exist in the host
  # (superproject) repo's object database.
  def async_subproject_commit_oid
    Platform::Loaders::GitTreeEntryAttributesAtPath.load(
      @superproject_repository, @superproject_commit_oid, path
    ).then do |ls_tree_result|
      ls_tree_result&.oid
    end
  end

  alias git_url url

  def url_is_linkable?
    url.start_with?("http") || github_repo?
  end

  def linkable_url
    if url.start_with?("http")
      url.chomp(".git")
    elsif github_repo?
      # convert github ssh clone url to a https link to the repo
      "#{GitHub.url}/#{@user}/#{@repo}"
    end
  end

  def github_repo?
    (
      url =~ /\Agit@#{Regexp.escape(GitHub.host_name)}/ ||
      url =~ self.class.relative_same_owner_regex ||
      url =~ self.class.relative_other_owner_regex
    ) && @user && @repo && repo?
  end

  def wiki?
    @is_wiki
  end

  def gist?
    @gist.present?
  end

  def repo?
    return false if wiki? || gist?
    true
  end

  def parse_github_url
    if match = self.class.gist_regex.match(url)
      @gist = Gist.active.find_by(repo_name: match[:repo_name])
      @user = @gist.try(:user_param)
    elsif match = self.class.repo_regex.match(url)
      @user = match[1]
      @repo = match[2]
      @repo.chomp!(".git")
      @is_wiki = !!@repo.chomp!(".wiki")
    elsif match = self.class.relative_same_owner_regex.match(url)
      @user = superproject_repository.owner_display_login
      @repo = match[1]
      @repo.chomp!(".git")
    elsif match = self.class.relative_other_owner_regex.match(url)
      @user = match[1]
      @repo = match[2]
      @repo.chomp!(".git")
    end
  end

  # These are methods because GitHub.host_name config variables and friends
  # can't be used at class load time, only at run time. Otherwise it breaks
  # migration processes on Enterprise.
  def self.gist_regex
    @gist_regex ||= begin
      host = /#{Regexp.escape(GitHub.gist_host_name)}/o
      unless GitHub.subdomain_isolation?
        host = %r{#{host}(/|:/?)gist/}
      end
      path = /(?<repo_name>([a-z0-9]{20}|[a-z0-9]{32})|\d+)(.git)?\z/
      /#{host}.*?#{path}/
    end
  end

  def self.repo_regex
    @repo_regex ||= %r{#{Regexp.escape(GitHub.host_name)}[/:]([\w-]+)/([\w.-]+)/?\Z}o
  end

  def self.relative_same_owner_regex
    @relative_same_owner_regex ||= /\A\.\.\/([\w.-]+)\/?\z/
  end

  def self.relative_other_owner_regex
    @relative_other_owner_regex ||= /\A\.\.\/\.\.\/([\w-]+)\/([\w.-]+)\/?\z/
  end
end
