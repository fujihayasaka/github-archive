# typed: false
# frozen_string_literal: true

module Repos::TreePayloadHelper
  include GitHub::Memoizer
  include ApplicationHelper
  include BlobMarkupHelper
  include LabelsHelper
  include SiteHelper
  include TextHelper
  include TreeHelper
  include CommitHelper
  include RepositoriesHelper
  include Commits::AuthorHelper
  include Repos::SshCertificateHelper

  extend T::Helpers
  extend T::Sig

  abstract!

  sig { abstract.returns(T.untyped) }
  def current_user; end

  def page_tree_payload(directory, include_readme, is_overview = false)
    all_shortcuts_enabled = current_user&.settings&.get(:keyboard_shortcuts_preference) == "all"
    time_key = "repos.payload.time"
    payload_tags = ["payload_type: tree"]
    GitHub.dogstats.distribution_time(time_key, tags: payload_tags) do
      if !is_overview
        file_tree, file_tree_processing_time, folders_to_fetch = ascend_tree(current_path)
      end
      {
        allShortcutsEnabled: all_shortcuts_enabled,
        path: path_string.empty? ? "/" : path_string,
        repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
        currentUser: Repos::ReactPayload.current_user_payload(current_user),
        refInfo: {
          name: tree_name,
          listCacheKey: ref_list_cache_key,
          canEdit: can_edit?,
          refType: tree_type,
          currentOid: commit_sha
        },
        tree: tree_payload(directory, include_readme),
        fileTree: file_tree,
        fileTreeProcessingTime: file_tree_processing_time,
        foldersToFetch: folders_to_fetch || []
      }
    end
  end

  def repo_error_payload(error)
    file_tree, file_tree_processing_time, folders_to_fetch = if current_path.empty?
      # For an invalid ref we cannot fetch the tree, so we'll just return no tree
      [nil, nil, []]
    else
      # When invalid path, let's only fetch the root directory.
      # We cannot determinate where is the invalid element.
      ascend_tree(RepositoryPath.new)
    end

    {
      path: path_string,
      repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
      refInfo: {
          name: tree_name,
          listCacheKey: ref_list_cache_key,
          canEdit: false,
          refType: helpers.tree_type,
          currentOid: commit_sha
        },
      currentUser: Repos::ReactPayload.current_user_payload(current_user),
      fileTree: file_tree,
      fileTreeProcessingTime: file_tree_processing_time,
      foldersToFetch: folders_to_fetch,
      allShortcutsEnabled: current_user&.settings&.get(:keyboard_shortcuts_preference) == "all",
      error: error
    }
  end

  def branch?
    current_repository.heads.exist?(tree_name)
  end

  def can_edit?
    return false if current_repository.archived? || current_repository.locked_on_migration?
    return false unless logged_in? && branch?
    return false if current_user.must_verify_email?
    current_user_can_push? || current_user_can_fork? || has_fork?
  end

  def has_fork?
    return false unless logged_in?
    return false if current_repository.archived? && current_user == current_repository.owner
    current_repository.network_has_fork_for?(current_user)
  end

  def tree_payload(directory, include_readme)
    {
      items: directory_items(directory),
      templateDirectorySuggestionUrl: template_directory_suggestion_url(directory),
      readme: include_readme ? readme_payload_timeboxed(directory) : nil,
      totalCount: directory.total_count,
      showBranchInfobar: show_branch_infobar?
    }
  end

  def template_directory_suggestion_url(directory)
    return nil unless directory.path == IssueTemplates.template_directory
    return nil if directory.repository.preferred_issue_templates.issue_template_config.configured?

    "#{GitHub.help_url}/articles/configuring-issue-templates-for-your-repository#configuring-the-template-chooser"
  end

  def readme_payload_timeboxed(directory)
    return nil unless directory.has_readme?

    GitHub::Timer.timeout(GitHub.git_template_timeout) do
      readme_payload(directory)
    end
  rescue GitRPC::Timeout, Timeout::Error => e
    Failbot.report_user_error(e)

    {
      displayName: directory.preferred_readme.name.b.force_encoding("utf-8").scrub!,
      errorMessage: "This preview took too long to generate.",
      timedOut: true,
    }
  end

  def readme_payload(directory)
    readme = directory.preferred_readme
    formatted_readme, toc = format_readme_with_toc(readme)
    if toc.present?
      toc.each do |toc_item|
        toc_item[:htmlText] = html_label_name(toc_item[:text])
      end
    end

    error_message = unless formatted_readme
      if readme.binary?
        "We can't display this README because it appears to contain binary data."
      else
        "There was an error when displaying this README."
      end
    end

    {
      displayName: readme.name.b.force_encoding("utf-8").scrub!,
      richText: formatted_readme,
      errorMessage: error_message,
      headerInfo: {
        toc: toc,
        siteNavLoginPath: site_nav_login_path,
      },
    }
  end

  def overivew_files_timeboxed(get_first_visible_file = false, tab_name = nil)
    start = Time.now
    overview_files = get_overview_files(tab_name)
    GitHub::Timer.timeout(request_time_left - 2.5) do
      [overview_files_payload(overview_files, get_first_visible_file, tab_name), time_diff_milli(start, Time.now)]
    end
  rescue GitRPC::Timeout, Timeout::Error => e
    Failbot.report_user_error(e)

    results = overview_files.map do |file|
      create_overview_file_payload(nil, file[:blob], file[:context], true)
    end

    [results, time_diff_milli(start, Time.now)]
  end

  def overview_files_payload(overview_files, get_first_visible_file = false, tab_name = nil)
    overview_files_to_render = overview_files
    overview_file_to_render_index = nil

    if get_first_visible_file
      if tab_name.present?
        if tab_name == "readme-ov-file"
          overview_file_to_render_index = overview_files.find_index { |file| file[:context][:preferred_file_type] == :readme }
        elsif tab_name == "coc-ov-file"
          overview_file_to_render_index = overview_files.find_index { |file| file[:context][:preferred_file_type] == :code_of_conduct }
        elsif tab_name == "security-ov-file"
          overview_file_to_render_index = overview_files.find_index { |file| file[:context][:preferred_file_type] == :security }
        else
          overview_file_to_render_index = overview_files.find_index { |file| tab_name == "#{file[:context][:tab_name]}-#{file[:context][:index]}-ov-file" }
        end
      end

      if overview_file_to_render_index.nil? &&
          (overview_files.any? { |file| file[:context][:preferred_file_type] == :readme } || (overview_files.present? && !should_recommend_readme?))
        overview_file_to_render_index = 0
      end

      if overview_file_to_render_index.nil?
        overview_files_to_render = []
      else
        overview_files_to_render = [overview_files[overview_file_to_render_index]]
      end
    end

    markedup_blobs = format_blobs_with_results(overview_files_to_render)

    if !get_first_visible_file
      markedup_blobs.map.with_index do |markedup_blob, index|
        create_overview_file_payload(markedup_blob, overview_files[index][:blob], overview_files[index][:context])
      end
    else
      overview_files.map.with_index do |overview_file, index|
        create_overview_file_payload(overview_file_to_render_index == index ? markedup_blobs[0] : nil, overview_file[:blob], overview_file[:context])
      end
    end
  end

  def prefill_directory_commit_short_messages(directory)
    commits_with_messages = []

    directory.each do |row|
      commit = row[:commit]
      next if commit.is_a? Directory::NilCommit
      next if commit.empty_message?

      commits_with_messages << commit
    end

    Commit.prefill_short_messages(commits_with_messages)
  end

  def commit_info_payload(directory)
    directory.to_h do |row|
      commit = row[:commit]
      return if commit.is_a? Directory::NilCommit

      content = row[:content]
      [content_name(content), {
        oid: commit.oid,
        url: commit_path(commit),
        date: commit.date,
        shortMessageHtmlLink: (commit_short_message_link(commit) unless commit.empty_message?),
      }]
    end
  end

  def branch_infobar_payload
    pull_request = with_database_error_fallback(fallback: false) do
      pull = current_repository.pull_requests.for_branch(current_branch_or_tag_name).last
      if pull && pull.open? && !pull.safe_user.spammy?
        pull
      else
        false
      end
    end

    {
      refComparison: ref_comparison,
      pullRequestNumber: pull_request ? pull_request.number : nil,
    }
  end

  def ref_comparison
    return nil unless current_branch_or_tag_name.present?

    base_branch = current_repository.base_branch(current_branch_or_tag_name, current_user)

    comparison = GitHub::Comparison.deprecated_build(current_repository, base_branch, commit_sha, base_repo: current_repository.parent)

    return nil unless comparison.valid?

    behind, ahead = comparison.relationship.map(&:to_i)

    base_branch_with_repo = current_repository.base_branch(current_branch_or_tag_name, current_user, include_remote_repo: true)
    base_branch_range = current_repository.base_branch(current_branch_or_tag_name, current_user, include_remote_repo: true, repo_seperator: ":")

    {
      behind: behind,
      ahead: ahead,
      baseBranch: base_branch_with_repo.frozen? ? base_branch_with_repo : base_branch_with_repo.force_encoding("utf-8").scrub,
      baseBranchRange: base_branch_range.frozen? ? base_branch_range : base_branch_range.force_encoding("utf-8").scrub,
      currentRef:  current_branch_or_tag_name.frozen? ? current_branch_or_tag_name : current_branch_or_tag_name.force_encoding("utf-8").scrub,
      isTrackingBranch: comparison.base_ref == current_branch_or_tag_name
    }
  end

  def latest_commit_info(commit, qualified_ref)
    author = commit.author_actor.visible_actor(current_user)
    author_path = if commit_author = author
      user_path(commit_author)
    else
      user_path(last_primary_author(commit)) unless commit.nil?
    end

    prefill_commit_author_associations([commit], current_user)
    commit_authors = initialize_commit_authors(commit, current_user)
    commit_link_options = { include_title: false }

    {
      oid: commit.oid,
      url: commit_path(commit),
      date: commit.date,
      shortMessageHtmlLink: (commit_short_message_link(commit, commit_path(commit), nil, commit_link_options) unless commit.empty_message?),
      bodyMessageHtml: commit&.message_body_html,
      author: {
        displayName: commit.author_name,
        # author login is nil when commit author does not have a GitHub account
        login: author&.display_login,
        path: author_path,
        avatarUrl: author&.primary_avatar_url(40) || User::AvatarList.default_image_url("gravatar-user-420"),
      },
      **commit_authors,
      status: commit.status_check_rollup&.state,
      isSpoofed: spoofed?(commit, qualified_ref)
    }
  end

  def name_for_codeload
    candidate_names = ["refs/heads/#{tree_name}".b, "refs/tags/#{tree_name}".b]

    ref = with_database_error_fallback(fallback: nil) { current_repository.refs.find_all(candidate_names).find(&:present?) }

    tree_type = if ref&.branch?
      "branch"
    elsif ref&.tag?
      "tag"
    else
      "tree"
    end

    case tree_type
    when "tag"
      "refs/tags/#{tree_name}"
    when "branch"
      "refs/heads/#{tree_name}"
    else
      tree_name
    end
  end

  def get_local_protocol_info
    ssh_certificates_required = current_user && current_repository.ssh_certificate_requirement_enabled?
    http_available = !ssh_certificates_required
    ssh_available = current_user && current_repository.ssh_enabled?
    ssh_certificates_available = ssh_available && can_use_ssh_certificates?(user: current_user, repository: current_repository)

    protocols = []
    protocols << :http if http_available
    protocols << :ssh if ssh_available
    protocols << :gh_cli

    ssh_url = ssh_available ? current_repository.ssh_url : nil
    http_url = http_available ? current_repository.http_url : nil
    host = GitHub.enterprise? ? "#{GitHub.host_name}/" : ""
    gh_cli_url = "gh repo clone #{host}#{current_repository.name_with_display_owner}"

    {
      httpAvailable: http_available,
      sshAvailable: ssh_available,
      httpUrl: http_available ? http_url : nil,
      showCloneWarning: current_user && current_user.public_keys.none? && !ssh_certificates_available,
      sshUrl: ssh_available ? ssh_url : nil,
      sshCertificatesRequired: ssh_certificates_required,
      sshCertificatesAvailable: ssh_certificates_available,
      ghCliUrl: gh_cli_url,
      defaultProtocol: determine_default_protocol(current_user_can_push?, protocols),
      newSshKeyUrl: new_settings_keys_ssh_key_path,
      setProtocolPath: user_set_protocol_path(current_user_can_push? ? "push" : "clone")
    }
  end

  def get_user_fork
    GitHub.dogstats.time("recently_touched_branches_view", tags: ["action:user_fork"]) do
      repo = current_repository.find_fork_in_network_for_user(current_user)
      repo if repo != current_repository
    end
  end

  def get_recent_branches(user_fork)
    recent_branches = []

    if current_user_can_push?
      current_repository.recently_touched_branches_for(current_user).each do |branch|
        recent_branches << branch.merge(repo: current_repository)
      end
    end

    if user_fork
      bad_oid = current_repository.default_oid
      user_fork.recently_touched_branches_for(current_user, bad_oid).each do |branch|
        recent_branches << branch.merge(repo: user_fork)
      end
    end

    if current_repository.merge_queue_enabled?
      recent_branches = recent_branches.reject { |b| b[:name].start_with?(MergeQueue::READ_ONLY_BRANCH_SHORT_PREFIX) }
    end

    recent_branches = recent_branches.sort_by { |b| b[:date] }.first(3)
  end

  def get_recently_touched_branches_live_update_channel
    user_fork = get_user_fork

    recent_branches = get_recent_branches(user_fork)

    channels = []

    if current_user_can_push?
      channels << GitHub::WebSocket::Channels.post_receive(current_repository, current_user)
    end

    if user_fork
      channels << GitHub::WebSocket::Channels.post_receive(user_fork, current_user)
    end

    recent_branches.each do |branch|
      channels << GitHub::WebSocket::Channels.branch(branch[:repo], branch[:name])
    end

    channels = channels.join(" ")

    unless channels.empty?
      data_channel = live_update_view_channel(channels)
    end

    data_channel
  end

  def ascend_tree(path, branch_name = tree_name, path_exists = true)
    ascend_timeout = 200
    max_items = 10000
    tree_folders = Hash.new
    folders_to_fetch = []
    start = Time.now
    prev_path = ""
    count = 0
    time_key = "repos.file_tree.time"
    found_first_directory = false
    GitHub.dogstats.distribution_time(time_key) do
      path.descend.reverse_each do |path_part|
        unless path_part == current_path && !current_path.empty?
          if (time_diff_milli(start, Time.now) > ascend_timeout || count > max_items) && prev_path
            tree_folders[path_part.to_s] = { items: [{ name: prev_path.split("/")[-1], path: prev_path, contentType: "directory" }] }
            folders_to_fetch << path_part.to_s
          else
            begin
              directory = current_repository.directory(branch_name, path_part.to_s)
              if directory
                directory_item = { items: directory_items(directory, path_part), totalCount: directory.total_count }
                if !path_exists && !found_first_directory
                  content_type = prev_path.empty? ? "file" : "directory"
                  item_path = prev_path.empty? ? path.to_s : prev_path
                  item = { contentType: content_type, name: item_path.split("/")[-1], path: item_path }
                  directory_item[:items].push(item)
                  directory_item[:totalCount] += 1
                  found_first_directory = true
                end
                tree_folders[path_part.to_s] = directory_item
                count += directory.total_count || 0
              end
            rescue GitRPC::NoSuchPath
              # this blob is supposed to exist, but it doesn't
              raise if path_exists

              # this blob only exists on the client, so we'll just insert the data manually
              content_type = prev_path.empty? ? "file" : "directory"
              item_path = prev_path.empty? ? path.to_s : prev_path
              item = { contentType: content_type, name: item_path.split("/")[-1], path: item_path }
              tree_folders[path_part.to_s] = { items: [item], totalCount: 1 }
            end
          end
          prev_path = path_part.to_s
        end
      end
    end
    [tree_folders, time_diff_milli(start, Time.now), folders_to_fetch]
  end

  private

  def spoofed?(commit, qualified_ref)
    # If we're showing a branch, it's resolved commit cannot be spoofed
    return false if qualified_ref.start_with?("refs/heads/")

    view = create_view_model(Commits::BranchListView, commit: commit)
    # A commit is spoofed if the list of branches containing it is empty
    view.branches_with_pull_requests.none? && !view.pr_search_problem
  end

  def time_diff_milli(start, finish)
    (finish - start) * 1000.0
  end

  def directory_items(directory, base_path = path_string)
    return [] unless directory.present?

    directory.map do |row|
      content = row[:content]
      item = {
        name: content_name(content),
        path: content.simplified_path || content.path,
        contentType: content_type(content)
      }
      has_simplified_path = ActiveModel::Type::Boolean.new.cast(content.simplified_path?)
      if content.submodule?
        title, tree = submodule_content_link(content, true, item[:path])
        item[:submoduleUrl] = tree
        item[:submoduleDisplayName] = title
      end
      item[:hasSimplifiedPath] = has_simplified_path if has_simplified_path
      item
    end
  end

  def content_name(content)
    name = content.respond_to?(:display_name) ? content.display_name : content.to_s

    if !content.submodule? && (content.tree? || content.blob?) && content.simplified_path?
      name = "#{content.simplified_utf8_path.gsub(/\A#{Regexp.escape(path_string_for_display)}\//, "")}"
    end

    name
  end

  def last_primary_author(commit)
    authors = commit.async_unique_visible_author_actors(current_user).sync
    primary_author = authors.first
    primary_author.async_visible_user(current_user).sync&.login
  end

  def license_spdx(license)
    if license.other?
      "Unknown"
    else
      license.spdx_id
    end
  end

  def is_not_viewable?(repository_license)
    return true unless repository_license.filepath.present?

    repository_license.license.other? && filename_not_license_like?(repository_license.filepath)
  end

  def filename_not_license_like?(filepath)
    filename = filepath.split("/").last
    filename.match(RepositoryLicense::FILENAME_REGEXP).nil?
  end

  def determine_default_protocol(pushable, protocols)
    selector = current_repository.protocol_selector(current_user)

    protocol_type = pushable ? :push_protocol : :clone_protocol
    selected = selector.send(protocol_type).to_sym
    suggested = GitHub.suggested_protocol.to_sym

    if protocols.include? suggested
      suggested
    elsif protocols.include? selected
      selected
    else
      protocols.first
    end
  end

  def get_overview_files(tab_name = nil)
    return [] unless current_directory.present?

    overview_files = []

    readme = current_repository.preferred_file(:readme, tree_name: current_directory.commitish)
    if readme
      readme_context = { preferred_file_type: :readme, tab_name: "README" }
      readme_markup_context = { path: File.dirname(readme.path), add_tabindex_to_headings: true }
      overview_files.push(blob: readme, context: readme_context, markup_context: readme_markup_context)
    end

    coc = current_repository.preferred_file(:code_of_conduct, tree_name: current_directory.commitish)
    if coc
      coc_context = { preferred_file_type: :code_of_conduct, tab_name: "Code of conduct" }
      overview_files.push(blob: coc, context: coc_context, markup_context: {})
    end

    if current_directory.commitish == current_repository.default_branch
      licenses = current_repository.repository_licenses
      viewable_licenses = licenses.reject { |repository_license| is_not_viewable?(repository_license) }

      if viewable_licenses.length == 0
        license = PreferredFile.find(directory: current_directory, type: :license)
        if license
          license_context = { preferred_file_type: :license, tab_name: "License", index: 1 }
          overview_files.push(blob: license, context: license_context, markup_context: {})
        end
      else
        index = 0
        viewable_licenses.each do |repository_license|
          license_blob = nil
          begin
            license_blob = current_repository.blob(tree_sha, repository_license.filepath.gsub(/^.\//, ""))
          rescue GitRPC::InvalidObject
          end
          if license_blob
            index += 1
            tab_name = license_spdx(repository_license.license) == "Unknown" ? "License" : license_spdx(repository_license.license)
            license_blob_context = { preferred_file_type: :license, tab_name: tab_name, index: index }
            overview_files.push(blob: license_blob, context: license_blob_context, markup_context: {})
          end
        end
      end
    else
      licenses = PreferredFile.find_all(directory: current_directory, type: :license)

      licenses.each do |license|
        license_blob_context = { preferred_file_type: :license, tab_name: "License" }
        overview_files.push(blob: license, context: license_blob_context, markup_context: {})
      end
    end

    security = current_repository.preferred_file(:security, tree_name: current_directory.commitish)
    if security
      security_context = { preferred_file_type: :security, tab_name: "Security" }
      overview_files.push(blob: security, context: security_context, markup_context: {})
    end

    overview_files
  end

  def create_overview_file_payload(markedup_blob, original_blob, context, timed_out = false)
    if markedup_blob.present?
      toc = markedup_blob[:result][:toc_headers_hash]

      toc_length = toc&.length || 0
      render_toc = toc_length > 0 && (GitHub.flipper[:overview_allow_unbounded_readme_toc].enabled? || toc_length <= 500)

      GitHub.dogstats.distribution("overview.readme_toc_length", toc_length)

      if render_toc
        toc.each do |toc_item|
          toc_item[:htmlText] = html_label_name(toc_item[:text])
        end
      end

      error_message = unless markedup_blob[:richtext]
        if original_blob.binary?
          "We can't display this file because it appears to contain binary data."
        else
          "There was an error when displaying this file."
        end
      end
    end

    if timed_out
      error_message = "This preview took too long to generate."
    end

    repo = original_blob.repository

    {
      displayName: original_blob.name.b.force_encoding("utf-8").scrub!,
      repoName: repo.name,
      refName: repo == current_repository ? current_directory.commitish : repo.default_branch,
      path: original_blob.path,
      preferredFileType: context[:preferred_file_type],
      tabName: context[:tab_name],
      richText: markedup_blob.present? ? markedup_blob[:richtext] : nil,
      loaded: markedup_blob.present? || timed_out,
      timedOut: timed_out,
      errorMessage: error_message,
      headerInfo: {
        toc: render_toc ? toc : nil,
        siteNavLoginPath: site_nav_login_path,
      }
    }
  end
end
