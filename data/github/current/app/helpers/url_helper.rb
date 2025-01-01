# typed: false
# frozen_string_literal: true

module UrlHelper
  extend T::Sig

  include GitHub::RouteHelpers
  include Discussions::OrgLevelDiscussionsUrlHelper
  include GitHub::ResilienceMixin

  def self.included(base)
    base.helper_method *instance_methods if base.respond_to? :helper_method # rubocop:disable GitHub/HelperMethodInHelper
  end

  # Public: Return [Web Origin](https://tools.ietf.org/html/rfc6454) for URI.
  #
  # uri - URI
  #
  # Returns String.
  def uri_origin(uri)
    raise "expected uri to be a URI but was #{uri.class}" unless uri.is_a?(URI)
    origin = "#{uri.scheme}://#{uri.host}"
    origin += ":#{uri.port}" if uri.port != 80 && uri.port != 443
    origin
  end

  # Public: Returns the given URL without a scheme.
  #
  # e.g. "https://developer.mozilla.org/en-US/docs/Web/JavaScript/" =>
  # "developer.mozilla.org/en-US/docs/Web/JavaScript"
  #
  # Returns a String or nil.
  def url_without_scheme(url)
    return unless url
    url.gsub(/\Ahttp[s]?:\/\//, "").gsub(/\/\z/, "")
  end

  # Public: Returns only the path from the given URL, with leading and trailing slashes removed.
  #
  # e.g. "https://github.com/facebook/react" => "facebook/react"
  #
  # Returns a String.
  def formatted_url_path(url)
    return unless url
    if url.is_a?(Hash)
      URI::HTTPS.build(url)
    else
      URI(url).path.gsub(/\A\//, "").gsub(/\/\z/, "")
    end
  end

  # Internal: Escape URL path components like javascript's encodeURIComponent()
  # URI and EscapeUtils get it wrong.
  #
  #   URI.escape 'a +b'
  #   # => "a%20+b"
  #   CGI.escape 'a +b'
  #   # => "a+%2Bb"
  #   EscapeUtils.escape_uri 'a +b'
  #   # => "a%20+b"
  #
  # This is what I want:
  #
  #   UrlHelper.escape_path 'a +b/c'
  #   # => "a%20%2Bb%2Fc"
  #
  #   # in a controller or view:
  #   escape_url_path 'a +b/c'
  #   # => "a%20%2Bb%2Fc"
  #
  # Returns an escaped String.
  def self.escape_path(str)
    return "" if str&.b.blank?
    # FIXME: This was lifted from Ruby in lib/uri/rfc2396_parser.rb
    # Why do we need to perform special escaping like this?
    # We should only apply special escaping to the things that need it,
    # then use the upstream escaping functions.  Copying this from Ruby for
    # now just to prevent warnings.
    str.b.gsub(URI_ESCAPE_RE) do
      us = $&
      tmp = "".dup
      us.each_byte do |uc|
        tmp << sprintf("%%%02X", uc)
      end
      tmp
    end.force_encoding(Encoding::US_ASCII).freeze
  end

  URI_ESCAPE_RE = /[^a-zA-Z\d\-\_\!\.\*'\(\)]/

  # regex pattern for valid host
  URL_HOST_PATTERN = /\A(?!-)[[:word:]\-\.]+(?<!-)\z/

  # Internal: Escape a Branch name for a URI path.  Branch names can have
  # slashes and colons.
  #
  #     escape_url_branch("a +b/c")
  #     # => "a%20%2Bb/c"
  #
  #     UrlHelper.escape_branch("person:feature/#23-skidoo")
  #     # => "person:feature/%2323-skidoo"
  #
  #     # in a controller or view:
  #     escape_url_branch("person:feature/#23-skidoo")
  #     # => "person:feature/%2323-skidoo"
  #
  # Returns an escaped String.
  def self.escape_branch(string, escape_plus: false)
    escaped = escape_path(string)
    if escape_plus
      escaped.b.gsub(BRANCH_ESCAPE_RE_PLUS, BRANCH_ESCAPES_PLUS)
    else
      escaped.b.gsub(BRANCH_ESCAPE_RE, BRANCH_ESCAPES)
    end
  end

  BRANCH_ESCAPE_RE = /%2F|%3A/
  BRANCH_ESCAPES = { "%2F" => "/", "%3A" => ":" }

  # Keep in sync with urlEncodeRef() in ref-selector.ts
  BRANCH_ESCAPE_RE_PLUS = /%2F|%3A|%2B/
  BRANCH_ESCAPES_PLUS = { "%2F" => "/", "%3A" => ":", "%2B" => "+" }

  def escape_url_paths(parts)
    parts.map { |p| escape_url_path(p) }.join("/")
  end

  # Internal: Escape URL path components like javascript's encodeURIComponent()
  # URI and EscapeUtils get it wrong.
  def escape_url_path(string)
    UrlHelper.escape_path(string)
  end

  # Internal: Escape a Branch name for a URI path.  Branch names can have
  # slashes and colons.
  #
  #     escape_url_branch("a +b/c")
  #     # => "a%20%2Bb/c"
  #
  #     escape_url_branch("person:feature/#23-skidoo")
  #     # => "person:feature/%2323-skidoo"
  #
  # Returns an escaped String.
  def escape_url_branch(string)
    UrlHelper.escape_branch(string)
  end

  def base_url
    if respond_to?(:request) && request
      "#{request.protocol}#{request.host_with_port}"
    else
      # Fall back to default host for Strat views
      GitHub.url
    end
  end

  def octocaptcha_help_url
    "#{GitHub.help_url}/articles/troubleshooting-connectivity-problems/#troubleshooting-the-captcha"
  end

  # Internal: Validates a hostname against RFC 952 and RFC 1123:
  #
  # * A host name can match letters or numbers
  # * A host name MUST NOT start or end with a '-' (dash)
  #
  # Returns a Boolean.
  def self.valid_host?(host)
    host.present? && host =~ URL_HOST_PATTERN
  end

  # Check whether a value is a valid URL.
  #
  # test - String to test.
  #
  # Returns Boolean.
  def self.valid_url?(test)
    uri = Addressable::URI.parse(test)
    uri = Addressable::URI.parse("http://#{test}") if uri.scheme.blank?

    return false unless uri.scheme =~ /https?/
    return false unless UrlHelper.valid_host?(uri.host)

    true
  rescue Addressable::URI::InvalidURIError => message
    false
  end

  def host_for_repo(repo)
    base_url
  end

  def repository_path(repo, *parts)
    repository_tree_path(repo, parts.first, :tree, parts[1..-1])
  end

  def repository_url(repo, *parts)
    host_for_repo(repo) + repository_path(repo, *parts)
  end

  def repository_url_to_main_site(repo, *parts)
    GitHub.url + repository_path(repo, *parts)
  end

  # Gets Go's import path for a repository.  Should be something like:
  #
  #   github.com/owner/repository
  #
  def go_import_url(repo)
    GitHub.host_name + repository_path(repo)
  end

  # Gets the Git URL for `go get` to download this package.
  def go_get_url(repo)
    "#{repository_url(repo)}.git"
  end

  def visual_studio_urls_enabled?
    return true if Rails.env.development?
    logged_in? && current_user.visual_studio_app_enabled?
  end

  def visual_studio_clone_url(repo = nil, pull_request = nil)
    return "https://windows.github.com" unless visual_studio_urls_enabled?

    uri = Addressable::URI.new
    uri.scheme = "git-client"
    uri.host = "clone"
    uri.query_values = { repo: repository_url(repo) }
    uri.to_s
  end

  def xcode_urls_enabled?
    return true if Rails.env.development?
    logged_in? && current_user.xcode_app_enabled?
  end

  def xcode_clone_url(repo = nil, pull_request = nil)
    return "https://developer.apple.com" unless xcode_urls_enabled?

    uri = Addressable::URI.new
    uri.scheme = "xcode"
    uri.host = "clone"
    uri.query_values = { repo: repository_url(repo) }
    uri.to_s
  end

  # Generate a URL to an individual diff's file.
  #
  # diffable - Commit | Comparison | PullRequest
  # path     - String path
  #
  # Returns String URL path.
  def diffable_file_path(diffable, path)
    encoded_path = Addressable::URI.encode_component(path, Addressable::URI::CharacterClasses::PATH)
    case diffable
    when Commit
      commit_path(diffable, current_repository, path)
    when GitHub::Comparison
      "#{diffable.to_path}/#{encoded_path}"
    when PullRequest
      "#{pull_request_path(diffable)}/files/#{encoded_path}"
    when GitHub::Unsullied::Comparison
      "/#{current_repository}/wiki/_compare/#{diffable.older}...#{diffable.newer}/#{encoded_path}"
    else
      raise TypeError, "unknown diff class: #{diffable.class}"
    end
  end

  # Public: URL for a comparison
  #
  # repo    - Repository for the comparison.
  # range   - A SHA/branch/tag for comparison.
  #           Can be specified as a range (using ...)
  # expand  - whether the comparison should be expanded (for a PR)
  #           defaults to false
  #
  # Returns a URL to the given comparison
  sig { params(repo: Repository, range: T.nilable(String), expand: T::Boolean).returns(String) }
  def compare_path(repo, range, expand: false)
    range = nil if range.present? && range == repo.default_branch
    range = UrlHelper.escape_branch(range, escape_plus: true) if range.present?
    url = ["", repo.name_with_display_owner, :compare, range].compact.join "/"
    expand ? "#{url}?expand=1" : url
  end

  # Generate options for diff path methods
  #
  # file_list_view - FileListView (view model), used to retrieve the following information:
  #   - current repository, which may be different from given head and/or base repo
  #   - diffs
  #   - diffs total line count
  #   - diffs total byte count
  #   - pull request number
  #   - commit sha
  #   - whether or not diffs are commentable
  # base_repository - Repository for diff base commit
  # head_repository - Repository for diff head commit
  #
  # Returns Hash of options
  def diffs_path_base_options(file_list_view, base_repository, head_repository)
    repo = file_list_view.repository
    diff = file_list_view.diffs
    base_user = base_repository.owner_display_login if base_repository && repo != base_repository
    head_user = head_repository.owner_display_login if repo != head_repository

    {
      base_user: base_user,
      head_user: head_user,
      sha1: diff.parsed_sha1,
      sha2: diff.parsed_sha2,
      base_sha: diff.base_sha,
      pull_number: file_list_view.pull.try(:number),
      commit: file_list_view.commit.try(:sha),
    }.tap do |options|
      options[:commentable] = true if file_list_view.commentable?
      options.merge! params.permit!.slice(*%i[diff skipmc shd _features ts])
    end
  end

  # Generate diffs path for given options
  #
  # file_list_view        - FileListView (view model)
  # base_repository       - Repository for diffs base commit
  # head_repository       - Repository for diffs head commit
  # start_entry           - Integer count of diff entries loaded (see FileListView#next_start_entry_index)
  # whitespace            - Boolean for whether whitespace should be ignored
  # sticky (optional)     - Boolean for whether view header is sticky
  # responsive (optional) - Boolean for whether view is responsive
  #
  # Returns String path
  # Example: "/monalisa/smile/diffs?base_user=monalisa&bytes=77&commentable=true&head_user=monalisa&lines=3&sha2=abc123&start_entry=1&sticky=false&w=1)"
  def diffs_path_for(file_list_view:, base_repository:, head_repository:, start_entry:, whitespace:, sticky: false, responsive: nil)
    repo = file_list_view.repository
    base_options = diffs_path_base_options(file_list_view, base_repository, head_repository)

    line_count = params[:lines].to_i + file_list_view.diffs.total_line_count
    byte_count = params[:bytes].to_i + file_list_view.diffs.total_byte_count
    file_type_filter = params.select { |k, _| k == FileFilterHelper::FILE_TYPE_FILTER_PARAM }
    show_deleted_files = params.select { |k, _| k == FileFilterHelper::SHOW_DELETED_FILES_FILTER_PARAM }
    manifest_files = params.select { |k, _| k == FileFilterHelper::MANIFESTS_PARAM }
    owned_files = params.select { |k, _| k == FileFilterHelper::CODEOWNER_PARAM }

    options = base_options.merge(
      start_entry: start_entry,
      bytes: byte_count,
      lines: line_count,
      short_path: params[:short_path],
      w: whitespace,
      sticky: sticky,
      responsive: responsive,
    )

    options.merge!(file_type_filter) if file_type_filter
    options.merge!(show_deleted_files) if show_deleted_files
    options.merge!(manifest_files) if manifest_files
    options.merge!(owned_files) if owned_files

    diffs_path(repo.owner_display_login, repo, options)
  end

  # Generate diff path for given options
  #
  # file_list_view        - FileListView (view model)
  # base_repository       - Repository for diff base commit
  # head_repository       - Repository for diff head commit
  # entry                 - Integer position of this diff entry in ordered list of all diff entries
  # whitespace            - Boolean for whether whitespace should be ignored
  # short_path (optional) - String short path for given diff (see DiffHelper#diff_short_path)
  # source (optional)     - Boolean for whether to display source diff
  #
  # Returns String path
  # Example: "/monalisa/smile/diffs/1?base_user=monalisa&commentable=true&head_user=monalisa&name=main&sha2=abc123&w=1"
  def diff_path_for(file_list_view:, base_repository:, head_repository:, entry:, short_path: nil, whitespace:, source: false)
    repo = file_list_view.repository
    base_options = diffs_path_base_options(file_list_view, base_repository, head_repository)

    options = base_options.merge(
      entry: entry,
      short_path: short_path,
      w: whitespace,
      name: file_list_view.tree_name,
    )
    options["source"] = true if source

    diff_path(repo.owner_display_login, repo, options)
  end

  def unchanged_files_with_annotations_path(file_list_view:)
    nwo = file_list_view.repository.name_with_display_owner

    blob_paths = file_list_view.annotations.non_diff_paths
    blob_paths = DiffsController::truncate_non_diff_blobs(blob_paths)

    params = {
      sha2: file_list_view.diffs.sha2,
      pull_number: file_list_view.pull.number,
      blob_paths: blob_paths,
    }

    "/#{nwo}/unchanged_files_with_annotations?#{params.to_query}"
  end

  def pre_mergeable_path(repo, range)
    range = escape_url_branch(range)
    range = nil if range == repo.default_branch
    ["", repo.name_with_display_owner, :branches, :pre_mergeable, range].compact.join "/"
  end

  # Generates the URL for suggested code reviewers on a new or
  # existing pull request.
  #
  # pull - A PullRequest.
  #
  # Returns a String URL path.
  def gh_suggested_reviewers_path(pull)
    if pull.persisted?
      suggested_reviewers_path(pull.repository.owner_display_login, pull.repository, pull.number)
    else
      comparison = pull.comparison
      range = "#{comparison.base}...#{comparison.head}"
      range = escape_url_branch(range)
      suggested_reviewers_range_path(comparison.repo.owner_display_login, comparison.repo, range)
    end
  end

  def submodule_content_url(submodule, content = nil, include_branch = true)
    path = h("/#{submodule.user}/#{submodule.repo}")

    if submodule.gist?
      # Override path to use a real url helper for Gist
      path = if content
        user_gist_at_revision_url(submodule.gist.user_param, submodule.gist, content.id, host: GitHub.gist_host_name)
      else
        user_gist_url(submodule.gist.user_param, submodule.gist, host: GitHub.gist_host_name)
      end
    elsif submodule.wiki?
      path += "/wiki"
      path += "/Home/#{content.id}" if content
    elsif content
      path += "/tree/#{content.id}"
    elsif submodule.branch && include_branch
      path += "/tree/#{submodule.branch}"
    end

    path
  end

  def real_user_path(user)
    "/users/#{user}"
  end

  # The standard Rails url helper is overridden here for performance reasons.
  # Hopefully when we're on a newer version of Rails that optimizes the route
  # helpers to not use url_for we won't need to do this.
  def user_path(user, format: nil, params: {}, **kwargs)
    raise "This is not a standard Rails helper. These options aren't supported: #{kwargs.keys}. See UrlHelper#user_path for supported arguments" if kwargs.any?

    # Mannequins do not have a #show page and thus should not be linked to
    return user.path if user.is_a?(Mannequin)

    path = "/#{user.to_param}"

    path << ".#{format}" if format

    path << "?#{params.to_query}" if params.any?

    path
  end

  def user_login(user)
    if user.is_a?(User)
      return GitHub::CurrentTenant.stafftools_tenant? ? user.login : user.display_login
    end

    user
  end

  def user_url(user)
    "#{base_url}/#{user_login(user)}"
  end

  def user_url_to_main_site(user)
    "#{GitHub.url}/#{user_login(user)}"
  end

  def org_dashboard_url_to_main_site(organization_id)
    "#{GitHub.url}/orgs/#{organization_id}/dashboard"
  end

  def clean_repository_path(repo, *parts)
    ["", repo.name_with_display_owner].join "/"
  end

  def fork_path(repo)
    ["", repo.name_with_display_owner, :fork].join "/"
  end

  include Porter::Urls

  # Public
  def global_notifications_path(options = {})
    # The global notifications path is independent of any list type.
    global_options = options.except(:list_type)

    "/notifications#{filter_notifications_query(global_options)}"
  end

  # Internal
  def filter_notifications_query(options)
    filter = options.fetch(:filter, params[:filter])
    all = options.fetch(:all, params[:all])
    list_type = options[:list_type]
    query_params = []

    if all.present?
      query_params << "all=1"
    elsif filter.present?
      query_params << "filter=#{escape_url_path(filter.to_s)}"
    end

    if list_type.present? && list_type.downcase == "team"
      query_params << "list_type=#{list_type}"
    end

    query_params.present? ? "?#{query_params.join('&')}" : nil
  end

  def edit_repository_path(*args)
    if args.size == 1
      repo = args.first
      ["", repo.name_with_display_owner, :settings].join "/"
    else
      super(*args)
    end
  end

  def update_repository_path(repo)
    ["", repo.name_with_display_owner, :settings, :update].join "/"
  end

  def archive_repository_path(repo)
    ["", repo.name_with_display_owner, :settings, :archive].join "/"
  end

  def unarchive_repository_path(repo)
    ["", repo.name_with_display_owner, :settings, :unarchive].join "/"
  end

  # Convenient helpers for creating a link into a repo path,
  # whether you're interested in commits, blob (raw, blame, &c),
  # tree, and more.
  #
  # Everything gets routed through one internal method to handle
  # escaping, path/parts passed as a string or array, and defaults.
  #
  # repo will be current_repository if not specified.

  # Public
  def commits_path(parts, tree, repo = nil)
    repository_tree_path(repo, tree, :commits, parts)
  end

  # Like commits_path, but a full URL
  def commits_url(*args)
    repo = args.last.is_a?(Repository) ? args.last : current_repository
    host_for_repo(repo) + commits_path(*args)
  end

  # Public
  def blob_view_path(parts, tree, repo = nil, anchor: nil)
    repository_tree_path(repo, tree, :blob, parts, anchor: anchor)
  end
  alias_method :blob_path, :blob_view_path

  def blob_view_url(*args)
    base_url + blob_view_path(*args)
  end

  # Public
  def blob_edit_path(parts, tree, repo = nil)
    repository_tree_path(repo, tree, :edit, parts)
  end

  # Public
  def blob_raw_path(parts, tree, repo = nil)
    repository_tree_path(repo, tree, :raw, parts)
  end

  # Public
  def blob_blame_path(parts, tree, repo = nil)
    repository_tree_path(repo, tree, :blame, parts)
  end

  # Public
  def blob_new_path(parts, tree, repo = nil)
    repository_tree_path(repo, tree, :new, parts)
  end

  # Public
  def blob_create_path(parts, tree, repo = nil)
    repository_tree_path(repo, tree, :create, parts)
  end

  def repository_upload_breadcrumb_path(path, tree)
    repo_uploads_path(current_repository.owner_display_login, current_repository, tree, path)
  end

  # Public
  def tree_path(path, tree, repo = nil)
    repository_tree_path(repo, tree, :tree, path)
  end

  def file_list_path(path, tree, repo = nil)
    repository_tree_path(repo, tree, "file-list", path)
  end

  # Public: The relative path to a preferred file (CONTRIBUTING, README, etc.)
  #
  # type - A Symbol type from PreferredFile::Types.
  # repository - Optionally, a Repository to find the file in. If not specified,
  #              we use current_repository.
  # tree_name - Optionally, a tree_name to find the file in. If not specified,
  #              we use the default_branch.
  #
  # Returns a String or nil.
  def preferred_file_path(type:, repository: nil, tree_name: nil)
    repository ||= current_repository
    return unless repository

    tree_name ||= repository.default_branch
    file = repository.preferred_file(type, tree_name: tree_name)
    return unless file

    if repository != file.repository
      tree_name = file.repository.default_branch
    end

    blob_view_path(file.path, tree_name, file.repository)
  end

  # Internal
  #
  # PERF This method has a fast path for when a normal string is passed as
  # parts. This is common and frequent on the, e.g., tree page where each tree
  # entry is linked to. We really want to avoid all this flattening, compacting,
  # and rejecting in that case. The root path for each repo, tree, action is
  # also cached since it requires a ton of escaping and array work.
  def repository_tree_path(repo, tree, action, parts, anchor: nil)
    repo ||= current_repository
    parts = parts[0] if parts.is_a?(Array) && parts.size == 1

    if action == :tree && parts.blank? && (tree&.b.blank? || with_database_error_fallback(fallback: false) { tree == repo.default_branch })
      return "/#{repo.name_with_display_owner}"
    end

    root_path = repository_tree_path_root(repo, tree, action)

    repo_tree_path = if parts.nil? || parts.empty?
      root_path
    elsif parts.is_a?(String)
      if parts[0] == "/"
        "#{root_path}#{escape_url_branch(parts)}"
      else
        "#{root_path}/#{escape_url_branch(parts)}"
      end
    else
      parts = parts.flatten.reject(&:blank?)
      escaped_parts = parts.map { |part| escape_url_branch(part) }
      [root_path, *escaped_parts].join("/")
    end

    return repo_tree_path unless anchor

    "#{repo_tree_path}##{escape_url_branch(anchor)}"
  end

  # Internal: Keeps a cache of root URL prefixes for a given repo, tree, action
  # trio. This is to reduce the amount of time spent in array operations and
  # escaping the same tree name over and over.
  def repository_tree_path_root(repo, tree, action)
    @repository_tree_path_root_cache ||= {}
    @repository_tree_path_root_cache["#{repo.name_with_display_owner}:#{tree}:#{action}"] ||=
      ["", repo.name_with_display_owner, action, escape_url_branch(tree)].join("/")
  end

  def commit_path(commit, repo = nil, path = nil, nwo = nil)
    nwo ||= begin
      repo ||= current_repository
      return unless repo.try(:owner)
      repo.name_with_display_owner
    end

    ["", nwo, "commit", commit, path].compact.join "/"
  end

  def commit_url(commit, repo = nil)
    commit_path(commit, repo)
  end

  def spoofed_commit_check_path(commit)
    ["", current_repository.name_with_display_owner, "spoofed_commit_check", commit].join "/"
  end

  def check_commit_quorum_path(commit)
    ["", current_repository.name_with_display_owner, "check_commit_quorum", commit].join "/"
  end

  def commit_branches_path(commit)
    ["", current_repository.name_with_display_owner, "branch_commits", commit].join "/"
  end

  def private_org_feed_path(*args)
    base  = super current_organization, current_user, *args
    token = current_user.signed_auth_token scope: "Atom:#{base}",
                                           expires: 50.years.from_now
    base + "?token=#{token}"
  end

  def private_feed_path(*args)
    base  = super current_user, *args
    token = current_user.signed_auth_token scope: "Atom:#{base}",
                                           expires: 50.years.from_now
    base + "?token=#{token}"
  end

  def home_url
    if logged_in? && saved_context
      base_url + saved_context.to_s
    else
      base_url + "/"
    end
  end

  def wiki_page_path(page = nil, version = nil)
    if !page
      return gh_wikis_path(current_repository)
    end
    url = gh_wiki_path(page, current_repository)
    if version
      url << "/#{version}"
    elsif page.name =~ /^home$/i
      url.sub! /\/home$/i, ""
    end
    url
  end

  def wiki_compare_path(page = nil, extra = nil)
    path = "_compare".dup
    path << "/#{extra}" if extra
    page ? wiki_page_path(page, path) : "#{wikis_path}/#{path}"
  end

  def wiki_revert_path(page = nil, extra = nil)
    path = "_revert".dup
    path << "/#{extra}" if extra
    page ? wiki_page_path(page, path) : "#{wikis_path}/#{path}"
  end

  def wiki_history_path(page = nil, extra = nil)
    path = "_history".dup
    path << "/#{extra}" if extra
    page ? wiki_page_path(page, path) : "#{wikis_path}/#{path}"
  end

  DANGEROUS_KEYS = [:only_path, :protocol, :host, :subdomain, :domain,
                    :tld_length, :port, :anchor, :trailing_slash, :script_name,
                    :params, :original_script_name].freeze

  # Builds a URL based on the values in options. Values understood by url_for
  # that are not forwarded to the Route module (eg. protocol, host, port,
  # etc...) are ignored.
  #
  # options - All options supported by ActionDispatch::Routing::UrlFor#url_for
  # that are forwarded to the Route module.
  #
  # Returns a URL.
  def safe_url_for(options = {})
    return options if options.is_a?(String)
    options = if options.is_a?(Hash)
      options.with_indifferent_access
    else
      options.permit!.to_h
    end

    # disgard params that have null bytes (avoids exceptions in url_for)
    options.except!(*DANGEROUS_KEYS).reject! { |name, _value| name.to_s.include?("\0") }

    url_for(options)
  end

  # Builds a URL based on the values in params. Values understood by url_for
  # that are not forwarded to the Route module (eg. protocol, host, port,
  # etc...) are ignored.
  #
  # options - A hash containing values that might exist in the params hash, but
  #           which should be overridden.
  #
  # Returns a URL.
  def url_with(options = {})
    safe_url_for(params.permit!.to_h.merge(options))
  end

  # Used on the "New Organization" page. Generates the right route for
  # the action you are performing.
  def create_or_transform_org_path
    org_transform? ? transform_organizations_path : organizations_path
  end

  # Give a dashboard context url for a user or an org.
  def context_path(context)
    if context.organization?
      org_dashboard_path(context)
    else
      "/"
    end
  end

  def organization_path(organization)
    "/organizations/#{organization.to_param}"
  end

  def settings_org_profile_path(organization)
    "#{organization_path(organization)}/settings/profile"
  end

  def settings_org_discussions_path(organization)
    "#{organization_path(organization)}/settings/discussions"
  end

  def org_owners_path(organization)
    org_people_path(organization, { "query" => "role:owner" })
  end

  def org_owners_url(organization)
    org_people_url(organization, { "query" => "role:owner" })
  end

  def new_org_repository_path(organization)
    "#{organization_path(organization)}/repositories/new"
  end

  def team_path(team, *args, organization: nil)
    super(organization || team.organization, team, *args)
  end

  def team_teams_path(team, *args)
    super(team.organization, team, *args)
  end

  def destroy_team_teams_path(team, *args)
    super(team.organization, team, *args)
  end

  def team_repositories_path(team, options = {})
    super(team.organization, team, options)
  end

  def team_repository_path(team, repo)
    super(team.organization, team, repo.id)
  end

  def team_repository_suggestions_path(team, options = {})
    super(team.organization, team, options)
  end

  def team_members_path(team, organization = nil, *args)
    super(organization || team.organization, team, *args)
  end

  def team_organization_role_path(team, organization)
    "#{organization_path(organization)}/settings/org_role_assignments?query=#{team.slug}+is%3Ateam"
  end

  def destroy_org_invitation_path(invitation, *args)
    super(invitation.organization, invitation, *args)
  end

  # Public: URL to return to after needing to sign in or up.
  #
  # Returns String URL.
  def return_to_path
    # If request is a simple XHR rendering a partial, we probably don't want
    # redirect the user to a broken XHR partial page. We want to return them to
    # the last full page they rendered.
    if request.xhr? && !pjax?
      request.referrer
    else
      request.original_url
    end
  end

  def login_path_with_return
    login_path(return_to: return_to_path)
  end

  def signup_path_with_return
    signup_path(return_to: return_to_path)
  end

  def add_account_path(return_to: nil)
    login_path(return_to: return_to || return_to_path, add_account: "1")
  end

  def issue_path(*args)
    if args[0].is_a?(Issue)
      issue = args.shift
      super(issue.repository.owner_display_login, issue.repository, issue, *args)
    else
      super
    end
  end

  def issue_url_to_main_site(*args)
    GitHub.url + issue_path(*args)
  end

  def discussion_url_to_main_site(*args)
    GitHub.url + discussion_path(*args)
  end

  def releases_path(entity)
    super(entity.owner, entity)
  end

  def repository_issues_path(options = {}, repo = nil)
    repo ||= current_repository
    repository_path(repo) + "/issues?" + options.to_query
  end

  def repository_pull_requests_path(options = {}, repo = nil)
    repo ||= current_repository
    repository_path(repo) + "/pulls?" + options.to_query
  end

  def pull_request_path(pull_request, repo = nil)
    repo ||= (pull_request.repository || current_repository)
    number = (pull_request.is_a?(Integer) ? pull_request : pull_request.number).to_s
    repository_path(repo) + "/pull/" + number
  end

  def pull_request_diff_range_path(pull_request, range: [])
    files_tab_path = "#{pull_request_path(pull_request)}/files"

    return files_tab_path unless range.all? { |oid| GitRPC::Util.valid_full_sha1?(oid) || oid == "HEAD" }

    range = range.dup
    range.shift if range.first == pull_request.base_sha
    return files_tab_path if range.blank?

    range.uniq!

    "#{files_tab_path}/#{range.join("..")}"
  end

  def discussion_path(discussion, repo = nil, query_params = {})
    repo ||= (discussion.repository || current_repository)
    number = (discussion.is_a?(Integer) ? discussion : discussion.number).to_s
    path = repository_path(repo) + "/discussions/" + number
    return path unless query_params.present?
    path + "?" + query_params.to_query
  end

  def discussion_comment_show_path_from(discussion:, comment_id:)
    "#{discussion_path(discussion)}##{DiscussionComment.dom_id(comment_id)}"
  end

  def mark_as_answer_discussion_comment_path(discussion_comment, repo = nil)
    "#{discussion_path(discussion_comment.discussion)}/comments/#{discussion_comment.id}/mark_as_answer"
  end

  def unmark_as_answer_discussion_comment_path(discussion_comment, repo = nil)
    "#{discussion_path(discussion_comment.discussion)}/comments/#{discussion_comment.id}/unmark_as_answer"
  end

  def issue_or_pull_request_path(issue)
    if issue.pull_request?
      pull_request_path(issue)
    else
      issue_path(issue)
    end
  end

  # Like pull_request_path, but a full URL
  def pull_request_url(pull_request, repo = nil)
    repo ||= (pull_request.repository || current_repository)
    host_for_repo(repo) + pull_request_path(pull_request, repo)
  end

  def pull_request_url_to_main_site(pull_request, repo = nil)
    GitHub.url + pull_request_path(pull_request, repo)
  end

  def stafftools_repository_pages_path(repo = nil)
    if repo.nil?
      super(current_repository.owner_display_login, current_repository)
    else
      super(repo.owner_display_login, repo)
    end
  end

  def stafftools_notifications_path(repo, newsies_thread)
    url = gh_notifications_stafftools_repository_path(repo)
    id = newsies_thread.respond_to?(:oid) ? newsies_thread.oid : newsies_thread.id
    url << "?thread=#{newsies_thread.class}%3B#{id}"
  end

  # Public: determines the URL base for referencing admin hosts. For dev and lab
  # machines, the base is empty to allow for relative URLs.
  #
  # Returns a string representing an absolute or relative base for hrefs
  def admin_host_url
    if GitHub.admin_frontend_enabled?
      "https://#{GitHub.admin_host_name}"
    else
      ""
    end
  end

  # Public: the default stafftools URL used as the rocket link
  #
  # Returns a string representing the default admin URL
  def admin_url
    if !logged_in?
      nil
    elsif current_user.github_developer?
      "https://devportal.githubapp.com"
    else
      "#{admin_host_url}/stafftools"
    end
  end

  def biztools_url
    if logged_in?
      "#{admin_host_url}/biztools"
    end
  end

  def new_release_path_helper(tag_name: nil, repo: nil, query_params: {})
    repo ||= current_repository
    query_params[:tag] = tag_name if tag_name
    new_release_path(repo.owner_display_login, repo, query_params)
  end

  def create_release_path(repo = nil)
    repo ||= current_repository
    repository_path(repo) + "/releases"
  end

  def release_path(release_or_tag_name, repo = nil, full_url: false)
    release_action_path(:tag, release_or_tag_name, repo, full_url: full_url)
  end

  def edit_release_path(release, repo = nil)
    release_action_path(:edit, release, repo)
  end

  def download_release_path(release, asset, repo = nil)
    release_action_path(:download, release, repo) + "/#{asset.name}"
  end

  def release_action_path(action, release_or_tag_name, repo = nil, full_url: false)
    repo ||= current_repository || release_or_tag_name.try(:repository)
    if release_or_tag_name.respond_to?(:tag_name)
      slug = release_or_tag_name.tag_name
    else
      slug = release_or_tag_name.to_s
    end

    base_url = if full_url
      repository_url(repo)
    else
      repository_path(repo)
    end

    base_url + "/releases/#{action}/#{escape_url_path(slug)}"
  end

  def edit_biztools_coupon_path(*args)
    if args[0].is_a?(Coupon)
      super(args[0].code)
    else
      super
    end
  end

  # Public: Wraps the params[:path] catch-all route param.
  #
  # Returns a RepositoryPath object.
  def current_path
    @current_path ||= RepositoryPath.new(params[:path])
  end

  # Public: Joins the params[:path] catch-all route param into a URL path.
  #
  # extra - Optional String that gets added to the end of the path.
  #
  # Returns a String URL path.
  def path_string
    current_path.to_s
  end

  def path_string_for_display
    current_path.for_display
  end

  def diff_path_anchor(path)
    "diff-#{Digest::SHA256.hexdigest(path)}"
  end

  # Compute hash/anchor for diff file box.
  #
  # path      - String path to file.
  # left_row  - String or Int row number to highlight on the right (added) side
  #             (optional, default: nil).
  # right_row - String or Int row number to highlight on the left (deleted) side
  #             (optional, default: nil).
  #
  # Returns String.
  def diff_file_anchor(path, left_row = nil, right_row = nil)
    anchor = "diff-#{Digest::SHA256.hexdigest(path)}"
    if left_row.present? && !right_row.present?
      "#{anchor}L#{left_row[0]}-L#{left_row[1]}"
    elsif right_row.present?
      "#{anchor}R#{right_row[0]}-R#{right_row[1]}"
    else
      anchor
    end
  end

  # Used for a discussion comment to create a link that's usable even after
  # the diff has become outdated, so links in old emails etc. are still useful.
  #
  # Also see ReviewCommentsHelper#review_comment_path which may obsolete this
  # when PR Versions are added.
  def comment_discussion_anchor(comment)
    "#{CommentsHelper::DISCUSSION_DOM_ID_PREFIX}#{comment.id}"
  end

  def branches_path(repository, view: :overview)
    url = super(repository.owner_display_login, repository.name)

    if view != :overview
      url << "/#{view}"
    end

    url
  end

  def repository_codespaces_path(repository)
    super(repository.owner_display_login, repository.name)
  end

  def installations_path(parent)
    if parent.is_a?(Repository)
      repository_installations_path(parent.owner_display_login, parent)
    elsif parent.is_a?(Organization)
      settings_org_installations_path(parent)
    elsif parent.is_a?(Business)
      hooks_enterprise_path(parent)
    else
      settings_user_installations_path
    end
  end

  def hooks_path(parent)
    if parent.is_a?(Repository)
      repository_hooks_path(parent.owner_display_login, parent)
    elsif parent.is_a?(Business)
      hooks_enterprise_path(parent)
    elsif parent.is_a?(Marketplace::Listing)
      marketplace_listing_hook_path(parent)
    else
      organization_hooks_path(parent)
    end
  end

  def new_hook_path(parent, options = {})
    if parent.is_a?(Repository)
      new_repository_hook_path(parent.owner_display_login, parent, options) # TODO: rename to repository_hooks_path
    elsif parent.is_a?(Business)
      new_hook_enterprise_path(parent, options)
    elsif parent.is_a?(Marketplace::Listing)
      new_marketplace_listing_hook_path(parent, options)
    else
      new_organization_hook_path(parent, options)
    end
  end

  def hook_path(hook, options = {})
    if hook.repo_hook?
      repository = hook.installation_target
      repository_hook_path(repository.owner_display_login, repository, hook, options)
    elsif hook.business_hook?
      hook_enterprise_path(hook.installation_target, hook, options)
    elsif hook.marketplace_listing_hook?
      marketplace_listing_hook_path(hook.installation_target, hook, options)
    elsif hook.sponsors_listing_hook?
      edit_sponsorable_dashboard_webhook_path(hook.installation_target.owner, hook, options)
    elsif hook.integration_hook?
      gh_settings_app_path(hook.installation_target)
    else
      organization_hook_path(hook.installation_target, hook, options)
    end
  end

  def hook_deliveries_path(hook, options = {})
    if hook.repo_hook?
      repository = hook.installation_target
      repository_hook_deliveries_path(repository.owner_display_login, repository, hook, options)
    elsif hook.org_hook?
      organization_hook_deliveries_path(hook.installation_target, hook, options)
    elsif hook.business_hook?
      hook_deliveries_enterprise_path(hook.installation_target, hook, options)
    elsif hook.integration_hook?
      if hook.installation_target.owner.organization?
        settings_org_app_hook_deliveries_path(hook.installation_target.owner, hook.installation_target.slug, hook, options)
      else
        settings_user_app_hook_deliveries_path(hook.installation_target.slug, hook, options)
      end
    elsif hook.marketplace_listing_hook?
      marketplace_listing_hook_deliveries_path(hook.installation_target.slug, hook, options)
    elsif hook.sponsors_listing_hook?
      sponsorable_dashboard_webhook_deliveries_path(hook.installation_target.sponsorable.display_login, hook, options)
    end
  end

  def hook_delivery_path(hook, guid, options = {})
    if hook.repo_hook?
      repository = hook.installation_target
      repository_hook_delivery_path(repository.owner_display_login, repository, hook, guid, options)
    elsif hook.org_hook?
      organization_hook_delivery_path(hook.installation_target, hook, guid, options)
    elsif hook.business_hook?
      hook_delivery_enterprise_path(hook.installation_target, hook, guid, options)
    elsif hook.integration_hook?
      if hook.installation_target.owner.organization?
        settings_org_app_hook_delivery_path(hook.installation_target.owner, hook.installation_target.slug, hook, guid, options)
      else
        settings_user_app_hook_delivery_path(hook.installation_target.slug, hook, guid, options)
      end
    elsif hook.marketplace_listing_hook?
      marketplace_listing_hook_delivery_path(hook.installation_target.slug, hook, guid, options)
    elsif hook.sponsors_listing_hook?
      sponsorable_dashboard_webhook_delivery_path(hook.installation_target.sponsorable.display_login, hook, guid, options)
    end
  end

  def pre_receive_update_hook_path(parent, hook, options = {})
    if parent.is_a?(Repository)
      update_repository_pre_receive_path(parent.owner_display_login, parent, hook, options)
    else
      update_organization_pre_receive_path(parent, hook, options)
    end
  end

  def stafftools_hooks_path(parent, options = {})
    if parent.is_a?(Business)
      stafftools_enterprise_hooks_path parent
    elsif parent.is_a?(Repository)
      stafftools_repo_hooks_path(parent.owner_display_login, parent, options)
    else
      stafftools_org_hooks_path(parent, options)
    end
  end

  def stafftools_toggle_hook_active_status_path(hook, options = {})
    if hook.business_hook?
      active_status_stafftools_enterprise_hook_path(hook.installation_target, hook, options)
    elsif hook.repo_hook?
      repository = hook.installation_target
      stafftools_repo_hook_toggle_active_status_path(repository.owner_display_login, repository, hook, options)
    elsif hook.integration_hook?
      toggle_hook_active_status_stafftools_user_app_path(hook.installation_target.owner, hook.installation_target.slug, options)
    elsif hook.sponsors_listing_hook?
      stafftools_sponsors_member_listing_webhook_toggle_active_status_path(hook.installation_target.owner, hook, options)
    else
      stafftools_org_hook_toggle_active_status_path(hook.installation_target, hook, options)
    end
  end

  def stafftools_hook_path(hook, options = {})
    if hook.business_hook?
      stafftools_enterprise_hook_path(hook.installation_target, hook, options)
    elsif hook.repo_hook?
      repository = hook.installation_target
      stafftools_repo_hook_path(repository.owner_display_login, repository, hook, options)
    elsif hook.integration_hook?
      stafftools_user_app_path(hook.installation_target.owner, hook.installation_target.slug, options)
    elsif hook.sponsors_listing_hook?
      stafftools_sponsors_member_listing_webhook_path(hook.installation_target.owner, hook, options)
    elsif hook.marketplace_listing_hook?
      biztools_marketplace_listing_hook_path(hook.installation_target.slug, options)
    else
      stafftools_org_hook_path(hook.installation_target, hook, options)
    end
  end

  def stafftools_repository_redirect_path(redirect)
    super(redirect.repository.owner_display_login, redirect.repository, redirect)
  end

  def projects_path(*args, owner:)
    type = if owner.is_a?(ActiveRecord::Base)
      owner.class.model_name
    else
      # It's coming from GraphQL
      owner.class.type.graphql_name
    end

    case type
    when "Repository"
      repo_projects_path(owner.owner.display_login, owner.name, *args)
    when "Organization"
      org_projects_path(owner.display_login, *args)
    when "User"
      user_projects_path(owner.display_login, *args)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_path(project, *args)
    type = if project.owner.is_a?(ActiveRecord::Base)
      project.owner.class.model_name
    else
      # It's coming from GraphQL
      project.owner.class.type.graphql_name
    end

    case type
    when "Repository"
      repo_project_path(project.owner.owner.display_login, project.owner.name, project.number, *args)
    when "Organization"
      org_project_path(project.owner.display_login, project.number, *args)
    when "User"
      user_project_path(project.owner.display_login, project.number, *args)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def edit_project_path(project, *args)
    owner_type = if project.owner.is_a?(ActiveRecord::Base)
      project.owner.class.model_name
    else
      # It's coming from GraphQL
      project.owner.class.type.graphql_name
    end

    case owner_type
    when "Repository"
      repo = project.owner
      edit_repo_project_path(repo.owner_display_login, repo, project.number)
    when "Organization"
      edit_org_project_path(project.owner.display_login, project.number, *args)
    when "User"
      edit_user_project_path(project.owner.display_login, project.number, *args)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_column_path(project, column)
    case project.owner
    when Repository
      repo = project.owner
      repo_project_column_path(repo.owner_display_login, repo, project, column)
    when Organization
      org_project_column_path(project.owner.display_login, project.number, column)
    when User
      user_project_column_path(project.owner.display_login, project.number, column)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_cards_path(project)
    case project.owner
    when Repository
      repo = project.owner
      repo_project_cards_path(repo.owner_display_login, repo, project)
    when Organization
      org_project_cards_path(project.owner, project)
    when User
      user_project_cards_path(project.owner, project)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_card_columns_path(project, card)
    case project.owner
    when Repository
      repo = project.owner
      repo_project_card_columns_path(repo.owner_display_login, repo, project, card)
    when Organization
      org_project_card_columns_path(project.owner, project, card)
    when User
      user_project_card_columns_path(project.owner, project, card)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_card_closing_references_path(card)
    project = card.project
    case project.owner
    when Repository
      repo = project.owner
      repo_project_card_closing_references_path(repo.owner_display_login, repo, project, card)
    when Organization
      org_project_card_closing_references_path(project.owner, project, card)
    when User
      user_project_card_closing_references_path(project.owner, project, card)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_card_closing_reference_path(card, pull)
    project = card.project
    case project.owner
    when Repository
      repo = project.owner
      repo_project_card_closing_reference_path(repo.owner_display_login, repo, project, card, pull.id)
    when Organization
      org_project_card_closing_reference_path(project.owner, project, card, pull.id)
    when User
      user_project_card_closing_reference_path(project.owner, project, card, pull.id)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_column_cards_path(project, column, *args)
    case project.owner
    when Repository
      repo = project.owner
      repo_project_column_cards_path(repo.owner_display_login, repo, project, column, *args)
    when Organization
      org_project_column_cards_path(project.owner, project, column, *args)
    when User
      user_project_column_cards_path(project.owner, project, column, *args)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_activity_path(project)
    case project.owner
    when Repository
      repo = project.owner
      repo_project_activity_path(repo.owner_display_login, repo, project)
    when Organization
      org_project_activity_path(project.owner, project)
    when User
      user_project_activity_path(project.owner, project)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_search_results_path(project, *args)
    case project.owner
    when Repository
      repo = project.owner
      repo_project_search_results_path(repo.owner_display_login, repo, project, *args)
    when Organization
      org_project_search_results_path(project.owner, project, *args)
    when User
      user_project_search_results_path(project.owner, project, *args)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_settings_path(project, *args)
    case project.owner
    when Organization
      org_project_settings_path(project.owner, project, *args)
    when User
      user_project_settings_path(project.owner, project, *args)
    else
      raise NotImplementedError, "Only org and user projects are supported"
    end
  end

  def project_settings_linked_repositories_path(project, *args)
    case project.owner
    when Organization
      org_project_settings_linked_repositories_path(project.owner, project, *args)
    when User
      user_project_settings_linked_repositories_path(project.owner, project, *args)
    else
      raise NotImplementedError, "Only org and user projects are supported"
    end
  end

  def project_settings_users_path(project, *args)
    case project.owner
    when Organization
      org_project_settings_users_path(project.owner, project, *args)
    when User
      user_project_settings_users_path(project.owner, project, *args)
    else
      raise NotImplementedError, "Only org and user projects are supported"
    end
  end

  def project_repository_results_path(project, *args)
    case project.owner
    when Organization
      org_project_repository_results_path(project.owner, project, *args)
    when User
      user_project_repository_results_path(project.owner, project, *args)
    else
      raise NotImplementedError, "Only org and user projects are supported"
    end
  end

  def project_card_path(card)
    project = card.project
    case project.owner
    when Repository
      repo = project.owner
      repo_project_card_path(repo.owner_display_login, repo, project, card)
    when Organization
      org_project_card_path(project.owner, project, card)
    when User
      user_project_card_path(project.owner, project, card)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_convert_note_to_issue_path(card)
    project = card.project
    case project.owner
    when Repository
      repo = project.owner
      repo_project_convert_note_to_issue_path(repo.owner_display_login, repo, project, card)
    when Organization
      org_project_convert_note_to_issue_path(project.owner, project, card)
    when User
      user_project_convert_note_to_issue_path(project.owner, project, card)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_update_note_path(card)
    project = card.project
    case project.owner
    when Repository
      repo = project.owner
      repo_project_update_note_path(repo.owner_display_login, repo, project, card)
    when Organization
      org_project_update_note_path(project.owner, project, card)
    when User
      user_project_update_note_path(project.owner, project, card)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_update_note_task_list_path(card)
    project = card.project
    case project.owner
    when Repository
      repo = project.owner
      repo_project_update_note_task_list_path(repo.owner_display_login, repo, project, card)
    when Organization
      org_project_update_note_task_list_path(project.owner, project, card)
    when User
      user_project_update_note_task_list_path(project.owner, project, card)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def archive_project_card_path(card)
    return "#" if card.id.nil?

    project = card.project

    case project.owner
    when Repository
      repo = project.owner
      archive_repo_project_card_path(repo.owner_display_login, repo, project, card)
    when Organization
      archive_org_project_card_path(project.owner, project, card)
    when User
      archive_user_project_card_path(project.owner, project, card)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def unarchive_project_card_path(card)
    return "#" if card.id.nil?

    project = card.project

    case project.owner
    when Repository
      repo = project.owner
      unarchive_repo_project_card_path(repo.owner_display_login, repo, project, card)
    when Organization
      unarchive_org_project_card_path(project.owner, project, card)
    when User
      unarchive_user_project_card_path(project.owner, project, card)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_search_archived_cards_path(project)
    case project.owner
    when Repository
      repo = project.owner
      repo_project_search_archived_cards_path(repo.owner_display_login, repo, project)
    when Organization
      org_project_search_archived_cards_path(project.owner, project)
    when User
      user_project_search_archived_cards_path(project.owner, project)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  def project_linkable_repositories_path(owner)
    case owner
    when Organization
      new_org_project_linkable_repositories_path(owner)
    when User
      new_user_project_linkable_repositories_path(owner)
    else
      raise NotImplementedError, "Only org and user projects support repository links"
    end
  end

  def card_pull_request_status_path(project, pull_request)
    case project.owner
    when Repository
      repo = project.owner
      repo_card_pull_request_status_path(repo.owner_display_login, repo, project, pull_request.id)
    when Organization
      org_card_pull_request_status_path(project.owner, project, pull_request.id)
    when User
      user_card_pull_request_status_path(project.owner, project, pull_request.id)
    else
      raise NotImplementedError, "Only repository, org, and user projects are supported"
    end
  end

  # Generates a Google Analytics Campaign tracking URL.
  #
  # NOTE: The following campaign parameters are required and an exception will
  # be raised if any are omitted:
  #
  # * source (referrer: explore-newsletter, verification-email)
  # * medium (marketing medium: banner, email, web)
  # * campaign (product or promo: github-email-verification, nps-email)
  #
  # The following parameters are optional:
  #
  # * term (keywords)
  # * content (use to differentiate click source)
  #
  # path         - Either a fully-qualified URL or path only.
  # query_params - Query params for the URL, including all campaign-related params.
  #                Omit the "utm" portion of campaign parameters.
  #
  # Examples
  #
  #   ga_campaign_url("/", {:source => "my-source", :campaign => "my-campaign"})
  #   # => "https://github.com/?utm_campaign=my-campaign&utm_medium=web&utm_source=my-source"
  #
  # Returns the campaign tracking URL as a string.
  def ga_campaign_url(path, query_params = {})
    default_query_params = { medium: "web" }
    GitHub::GACampaignURL.new(path, query_params.reverse_merge(default_query_params)).to_s
  end

  # Internal: ensure that Atom feed URLs for private repositories accessible to
  # a logged-in user have a valid authentication token in the query string.
  #
  # See github/enterprise#244 for why the private_mode_enabled? check exists.
  #
  # url - the String feed URL
  #
  # Examples
  #
  #   # Public repo, no token required.
  #   tokenized_feed_url("https://github.com/bbc/public/commits/topgear.atom")
  #   # => "https://github.com/bbc/public/commits/topgear.atom"
  #
  #   # Private repo, only authorized users may access using a token.
  #   tokenized_feed_url("https://github.com/bond/eyesonly/commits/q.atom")
  #   # => "https://github.com/bond/eyesonly/commits/q.atom?token=secretoauththing"
  #
  # Returns a URL String.
  def tokenized_feed_url(url)
    if (current_repository.private? || GitHub.private_mode_enabled?) && logged_in?
      uri = URI.parse(url)
      token = current_user.signed_auth_token scope: "Atom:#{uri.path}",
                                             expires: 50.years.from_now
      uri.query = Rack::Utils.parse_query(uri.query).merge(token: token).to_query
      uri.to_s
    else
      url
    end
  end

  # Builds a URL to the Apple App Store for the GitHub Mobile iOS app.
  #
  # See https://help.apple.com/app-store-connect/en.lproj/static.html#itcfa7936330
  #
  # Returns a URL String.
  def ios_mobile_app_store_url(campaign: "default", provider_token: 524675)
    uri = Addressable::URI.parse("https://apps.apple.com/app/apple-store/id1477376905")
    uri.query_values = { ct: campaign, pt: provider_token, mt: 8 }
    uri.to_s
  end

  # Builds a URL to the Google Play Store for the GitHub Mobile Android app.
  #
  # See https://developers.google.com/analytics/devguides/collection/android/v4/campaigns#google-play-url-builder
  #
  # Returns a URL String.
  def android_mobile_app_store_url(campaign: "default", source: "github", medium: "web", content: nil, term: nil)
    uri = Addressable::URI.parse("https://play.google.com/store/apps/details")

    referrer_param = {
      utm_campaign: campaign,
      utm_content: content,
      utm_medium: medium,
      utm_source: source,
      utm_term: term,
    }.compact.to_query

    # Google Play Store URL's require a URL encoded referrer.
    uri.query = "id=com.github.android&referrer=#{ERB::Util.url_encode(referrer_param)}"
    uri.to_s
  end

  # Used to sanitize URLs passed into 'a' tags from user params. By
  # default only onsite URLs are considered safe. Additional safe hosts can be
  # passed as an option to allow offsite links.
  #
  # url      - String URL, usually from params[]
  # options - Optional hash with the following parameters:
  #           :fallback        - The url to return if `url` points to a
  #                              disallowed off-site URL.
  #           :allow_hosts     - An array of hosts that are allowed.
  #                              By default this method only allows
  #                              links to onsite hosts (default: []).
  #           :allow_query     - Allow query string for offsite hosts
  #                              (default: false)
  #           :allow_fragment  - Allow fragment for offsite hosts
  #                              (default: false)
  #           :any_http        - Allow all URLs (onsite or offsite)
  #                              i.e only block javascript + non-http schemes
  #                              (default: false)
  #
  # Returns a String containing the URL - either the original url, or a fallback.
  def sanitize_url(url, options = {})
    return nil if url.blank?
    fallback = options.delete(:fallback) || "#{request.base_url}/"
    url ||= fallback
    allow_hosts = options.delete(:allow_hosts) || []
    allow_query = options.delete(:allow_query)
    allow_fragment = options.delete(:allow_fragment)
    any_http = options.delete(:any_http)

    begin
      # replace 2+ leading slashes with exactly // to prevent leading slash abuse, something like /\/\/\/example.com being considered relative and safe
      parsed_url = Addressable::URI.parse(url.gsub(/\A[\\\/]{2,}(.+)/, "//\\1"))
    rescue Addressable::URI::InvalidURIError => boom
      Failbot.report(boom, unparsable_url: url)
      GitHub.dogstats.increment("sanitize_url.fallback.invalid_uri")
      return fallback
    end

    http_scheme = %w[https http].include?(parsed_url.scheme)
    contains_user_info = !parsed_url.userinfo.nil?

    onsite_absolute_url =
      parsed_url.absolute? &&
      http_scheme &&
      parsed_url.host == request.host &&
      (parsed_url.port.nil? || parsed_url.port == request.port)

    # Checking parsed_url.host == request.host is necessary in onsite_relative_url
    # for "protocol-relative" urls such as "//github.com/foo/bar"
    # where parsed_url.relative? => true and parsed_url.host => "github.com"
    onsite_relative_url =
      parsed_url.relative? &&
      (parsed_url.host.nil? || parsed_url.host == request.host) &&
      (parsed_url.port.nil? || parsed_url.port == request.port)

    allowed_offsite_absolute_url =
      parsed_url.absolute? &&
      http_scheme &&
      allow_hosts.include?(parsed_url.host) &&
      (parsed_url.port.nil? || parsed_url.port == request.port) &&
      (parsed_url.fragment.nil? || allow_fragment) &&
      (parsed_url.query.nil? || allow_query)

    allowed_http =
      http_scheme &&
      any_http &&
      (parsed_url.port.nil? || parsed_url.port == request.port)

    allowed_url =
      onsite_absolute_url ||
      onsite_relative_url ||
      allowed_offsite_absolute_url ||
      allowed_http

    if allowed_url && !contains_user_info
      url = parsed_url.to_s
    else
      url = fallback
      GitHub.dogstats.increment("sanitize_url.fallback.not_allowed")
    end

    url
  end

  def move_work_repositories_path(account, options = {})
    return org_move_work_repositories_path(account, options) if account.organization?

    user_move_work_repositories_path(options)
  end

  def move_work_projects_path(account, options = {})
    return org_move_work_projects_path(account, options) if account.organization?

    user_move_work_projects_path(options)
  end

  def move_work_memex_projects_path(account, options = {})
    return org_move_work_memex_projects_path(account, options) if account.organization?

    user_move_work_memex_projects_path(options)
  end

  def new_move_work_path(account, options = {})
    return org_move_work_new_path(account, options) if account.organization?

    user_move_work_new_path(options)
  end

  def move_work_choose_resources_path(account)
    return org_move_work_choose_resources_path(account) if account.organization?

    user_move_work_choose_resources_path
  end

  def move_work_new_choose_organization_path(account, options = {})
    return new_org_move_work_choose_organization_path(account, options) if account.organization?

    new_user_move_work_choose_organization_path(options)
  end

  def move_work_choose_organization_path(account)
    return org_move_work_choose_organization_path(account) if account.organization?

    user_move_work_choose_organization_path
  end

  def move_work_confirmation_page_path(account)
    return new_org_move_work_confirmation_path(account) if account.organization?

    new_user_move_work_confirmation_path
  end

  def move_work_confirm_path(account)
    return org_move_work_confirmation_path(account) if account.organization?

    user_move_work_confirmation_path
  end

  ENTERPRISE_TRIAL_REFERRAL_KEYS = %i(ref_page ref_cta ref_loc)

  def enterprise_trial_referral_params(additional_params: {})
    ENTERPRISE_TRIAL_REFERRAL_KEYS.inject({}) { |m, v| m[v] = params[v]; m }.reject { |_k, v| v.blank? }.merge(additional_params)
  end

  def enterprise_trial_signup_path(organization = nil, params: {})
    if organization.present?
      enterprise_trial_accounts_new_organization_path(organization, enterprise_trial_referral_params(additional_params: params))
    else
      enterprise_trial_accounts_new_path(enterprise_trial_referral_params(additional_params: params))
    end
  end
end
