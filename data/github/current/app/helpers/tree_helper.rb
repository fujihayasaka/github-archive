# typed: false
# frozen_string_literal: true

require "cache_key_logging_denylist"

module TreeHelper
  include GitHub::Encoding
  include GitHub::UTF8

  def deeper_tree_path(path, base_path = path_string)
    tree_path [base_path, path].join("/"), tree_name
  end

  def deeper_blob_path(path, base_path = path_string)
    blob_path [base_path, path].join("/"), tree_name
  end

  def commit_tree_path(commit)
    tree_path path_string, commit
  end

  def content_type(content)
    if content.tree?
      :directory
    elsif content.submodule?
      :submodule
    elsif content.symlink?
      target = if content.respond_to?(:symlink_target_oid) && content.symlink_target_oid
        current_repository.read_objects(
          [content.symlink_target_oid]).first
      end

      # everything that's not a file or another symlink, is a directory
      if target && target["type"] == "tree"
        :symlink_directory
      else
        :symlink_file
      end
    else
      :file
    end
  end

  # Public: Get the URL for some git content.
  #
  # content - Content to get the URL for. Should be a TreeEntry, but can also
  # be anything that responds to #to_s.
  #
  # Returns a string.
  def content_url(content, base_path = path_string)
    name = content.respond_to?(:name) ? content.name : content.to_s
    url  = nil

    if content.respond_to?(:blob?) && content.blob?
      url = deeper_blob_path(name, base_path)
    elsif content.respond_to?(:submodule?) && content.submodule?
      submodule = submodule_for(content)
      if submodule && submodule_linkable?(submodule)
        url = submodule_content_url(submodule)
      end
    else
      # Use tree path for everything else
      url = if content.respond_to?(:simplified_path?) && content.simplified_path?
        tree_path(content.simplified_path, tree_name)
      else
        deeper_tree_path(name, base_path)
      end
    end

    url
  end

  # Public: Return the commit count from the passed oid, by default it uses the current_repository,
  # however a repo can be passed in as well.
  #
  # No limit is passed to the RPC method, so it should always return
  # the correct number
  #
  # Returns a string.
  def limitless_commit_count(oid, repo = nil)
    repo ||= current_repository
    count = repo.rpc.fast_commit_count(oid, nil, timeout: 2)
    number_with_delimiter count
  rescue GitRPC::Timeout
    # It should never take this long to retrieve the "fast" commit count. Most likely the
    # bitmap for the repo is missing. It's not safe to automatically generate it here though
    # as an availability incident could trigger timeouts resulting in large numbers
    # of erroneous recalculation attempts. Log this failure so we can monitor it in aggregate.
    GitHub.dogstats.increment("fast_commit_count.timeout")
    ""
  end

  def submodule_linkable?(submodule)
    submodule.gist || submodule.user && submodule.repo
  end

  def submodule_for(content, content_path = nil)
    submodule_path = content_path || File.join(path_string, content.name)
    current_repository.submodule(commit_sha, submodule_path)
  end

  def submodule_content_link(content, is_tree_view = false, content_path = nil)
    submodule = submodule_for(content, content_path)

    if submodule
      title = "#{content.display_name} @ #{content.id[0..6]}"

      content = if submodule_linkable?(submodule)
        path = submodule_content_url(submodule)
        tree = submodule_content_url(submodule, content)

        return link_to(title, tree) unless is_tree_view
        return title, tree
      else
        title
      end
      return content_tag :span, content, title: title unless is_tree_view
      content
    else
      # for some reason, no .gitmodules file was found,
      # or this submodule couldn't be found.
      return h(content.display_name) unless is_tree_view
      content.display_name
    end
  end

  # The readme for the current tree and path.
  #
  # Returns a Repository::PreferredReadme.
  def current_readme
    return @current_readme if defined?(@current_readme)

    @current_readme = current_directory.preferred_readme
  end

  # Find out whether or not there's a readme at the current tree and
  # path.
  #
  # Returns a boolean.
  def has_readme?
    current_readme.present?
  rescue => e # rubocop:todo Lint/GenericRescue
    failbot e
    false
  end

  # The extension of the readme, formatted as a class.
  #
  # Returns a String (blank if there's no README).
  def readme_extension_class_name(readme = nil)
    if readme = readme || current_readme
      utf8(readme.extension.to_s.sub(".", "").gsub(/\s+/, ""))
    else
      ""
    end
  rescue => e # rubocop:todo Lint/GenericRescue
    failbot e
    ""
  end

  # Should we recommend that you add a README?
  def should_recommend_readme?
    params[:path].blank? &&
      current_user_can_push? &&
      current_directory &&
      !current_directory.truncated? &&
      !current_repository.user_configuration_repository? &&
      !current_repository.archived?
  end

  # Like current_branch_or_tag_name but returns immediately if the request
  # parameter for the branch/tag name is not present and so URLs being generated
  # don't need to consider it at all
  def current_branch_or_tag_name_for_urls
    current_branch_or_tag_name if params[:name].present?
  end

  def current_branch_or_tag_name
    return @current_branch_or_tag_name if defined? @current_branch_or_tag_name
    @current_branch_or_tag_name =
      if params[:name].blank?
        if repository_offline?
          "master"
        else
          current_repository.default_branch
        end
      elsif repository_offline?
        params[:name]
      else
        exists = with_database_error_fallback(fallback: false) do
          begin
            current_repository.refs.exist?(params[:name])
          rescue GitRPC::Timeout
            false
          end
        end
        exists ? params[:name] : nil
      end
  end

  def unqualified_branch_or_tag_name
    # Removes only the first occurrence
    qualified_tree_name&.b.sub(%r{\Arefs/heads/|refs/tags/}, "") || current_branch_or_tag_name
  end

  def show_branch_rename_instructions_popover?(tree_type:)
    tree_type == "branch" &&
      current_branch_or_tag_name == current_repository.default_branch &&
      !current_user&.dismissed_repository_notice?("repo_default_branch_rename",
        repository_id: current_repository.id) &&
      current_repository.branch_recently_renamed?(current_branch_or_tag_name) &&
      current_repository.writable_by?(current_user)
  end

  def show_parent_branch_rename_instructions_popover?(tree_type:)
    return false unless tree_type == "branch"
    return false unless current_branch_or_tag_name == current_repository.default_branch

    parent_repo = current_repository.parent
    return false unless parent_repo

    parent_default_branch = parent_repo.default_branch
    return false if parent_default_branch == current_branch_or_tag_name

    has_dismissed_popover = current_user&.dismissed_repository_notice?(
      "repo_parent_default_branch_rename",
      repository_id: current_repository.id
    )
    return false if has_dismissed_popover

    return false unless current_repository.adminable_by?(current_user)

    parent_repo.branch_recently_renamed?(parent_default_branch)
  end

  def latest_default_branch_rename
    current_repository.branch_rename_for(new_name: current_repository.default_branch)
  end

  def display_current_branch_or_tag_name
    unqualified_branch_or_tag_name.try { |s| utf8(s.dup) }
  end

  def branch_or_tag_name
    current_branch_or_tag_name || current_repository.default_branch
  end

  # Format a commit message as HTML and truncate anything over 72 characters.
  # The Commit#commit_message should be used instead when a Commit object
  # is available.
  def format_commit_message_short(message, repository)
    context = {
      entity: repository || try(:current_repository),
      base_url: base_url,
    }

    cache_key = [
      CacheKeyLoggingDenylist::TREE_HELPER_PREFIX,
      Digest::SHA256.hexdigest(message),
      context[:entity].try(:name_with_owner),
      "v2",
    ].join(":")

    GitHub.cache.fetch(cache_key) do
      format_commit_message_short!(message, context)
    end
  end

  def format_commit_message_short!(message, context = {})
    commit_message = Commits::CommitMessageHTML.new(message, context)
    commit_message.subject
  end

  def default_branch?
    return false unless current_repository.git
    [current_repository.default_branch, current_repository.default_oid].include?(tree_name)
  end

  def finder_newb?
    logged_in? && !current_user.dismissed_notice?("tree_finder_help")
  end

  # Show the branch information bar? Shows some quick stats about the branch,
  # and all of the discussable information related to it.
  def show_branch_infobar?
    return false if tree_type != "branch"
    return true if current_repository.fork?

    current_branch_or_tag_name != current_repository.base_branch(current_branch_or_tag_name, current_user)
  end
end
