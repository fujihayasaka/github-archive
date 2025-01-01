# typed: true
# frozen_string_literal: true

module Commit::ReactPayloadDataDependency

  include ActionView::Helpers::NumberHelper
  include BlobMarkupHelper
  include Commits::AuthorHelper
  include Commits::ReactPayloadDataDependency
  include Commit::ReactDiffLinesHelper
  include DiffLineChangeMarker
  include DiffHelper
  include CommitHelper
  include FailbotHelper
  include UrlHelper
  include TextHelper
  include AvatarHelper
  include StaticAssetHelper

  def commit_show_payload(current_repository:, current_commit:, file_list_view:, current_user:, diff_view:, short_path:, ignore_whitespace:, full_path:, has_copilot_access: false)
    {
      commit: build_commit_payload(current_commit, current_user),
      currentUser: Repos::ReactPayload.current_user_payload_for_diff(current_user),
      repo: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: false, # we don't need this for the commit view so dont bother fetching it
      ),
      diffEntryData: build_file_diff_payload_with_file_list(file_list_view, current_user, short_path, has_copilot_access: has_copilot_access).as_json(only: ALLOWED_DIFF_JSON_FIELDS),
      splitViewPreference: diff_view.to_s,
      ignoreWhitespace: ignore_whitespace,
      repoOwnerGlobalRelayId: current_repository.owner.global_relay_id,
      commentsPreference: current_user.present? ? current_user.settings.get(:diff_comments_preference) : UserSettings::DIFF_COMMENTS_PREFERENCES[0], #visible
      diffLineSpacingPreference: current_user.present? ? current_user.settings.get(:diff_line_spacing) : Commit::DiffLineSpacing::RELAXED,
      useMonospaceFont: current_user&.use_fixed_width_font? || false,
      pasteUrlLinkAsPlainText: current_user&.paste_url_link_as_plain_text? || false,
      userNotices: build_user_notices_payload(current_user),
      path: full_path,
      fileTreeExpanded: current_user.present? ? current_user.settings.get(:pull_request_file_tree_visible) : true,
      headerInfo: {
        additions: file_list_view.total_additions,
        deletions: file_list_view.total_deletions,
        filesChanged: file_list_view.diffs.summary.changed_files,
        filesChangedString: number_with_delimiter(file_list_view.diffs.summary.changed_files),
      },
      moreDiffsToLoad: file_list_view.load_more?,
      asyncDiffLoadInfo: {
        startIndex: file_list_view.next_start_entry_index,
        truncated: file_list_view.truncated?,
        byteCount: file_list_view.diffs.total_byte_count,
        lineShownCount: file_list_view.diffs.total_line_count,
      },
      commentInfo: {
        canComment: current_commit.can_comment?(current_user),
        locked: current_commit.locked?,
        canLock: current_commit.lockable_by?(current_user),
        repoArchived: current_repository.archived?
      },
    }
  end

  def build_user_notices_payload(current_user)
    return [] unless current_user

    compact_diff_lines_notice = {
      name: UserNotice::COMPACT_DIFF_LINES_NOTICE,
      dismissed: current_user.dismissed_notice?(UserNotice::COMPACT_DIFF_LINES_NOTICE),
    }

    [compact_diff_lines_notice]
  end

  def build_commit_payload(commit, current_user)
    prefill_core_commit_associations([commit], current_user, message_render_type: CommitMessageRenderType::FullSubject)

    {
      **build_core_commit_payload(commit, current_user, message_render_type: CommitMessageRenderType::FullSubject),
      parents: commit.parent_oids,
      globalRelayId: commit.global_relay_id,
      sha1: commit.diff.parsed_sha1,
      sha2: commit.diff.parsed_sha2,
    }
  end

  # copied from app/platform/interfaces/diff_delta.rb - figure out how to import this
  sig { params(status: String).returns(T.any(Platform::Enums::PatchStatus, Symbol)) }
  def change_type(status)
    case status
    when "D" then :deleted
    when "A" then :added
    when "M" then :modified
    when "R" then :renamed
    else :unknown
    end
  end

  def new_tree_entry(diff, repo)
    return nil if diff.deleted?

    ::TreeEntry.new(repo, new_info_from_diff_entry(diff))
  end

  def old_tree_entry(diff, repo)
    return nil if diff.added?

    ::TreeEntry.new(repo, old_info_from_diff_entry(diff))
  end

  def new_info_from_diff_entry(diff)
    { "path" => diff.b_path || "", "mode" => diff.b_mode, "oid" => diff.b_blob, "type" => "blob" }
  end

  def old_info_from_diff_entry(diff)
    { "path" => diff.a_path || "", "mode" => diff.a_mode, "oid" => diff.a_blob, "type" => "blob" }
  end

  def get_prefilled_tree_entries(file_list_view, use_styling_directives: false, use_better_generated_logic: false)
    new_tree_entries = []
    old_tree_entries = []

    file_views = file_list_view.each_diff.to_a
    if use_better_generated_logic
      content_tree_entries = file_views.map(&:diff_blob).reject(&:nil?)
      TreeEntry.load_attributes!(content_tree_entries, file_list_view.attributes_commit_oid)
    end

    file_views.each do |diff|
      new_tree_entries << new_tree_entry(diff.diff, file_list_view.repository)
      old_tree_entries << old_tree_entry(diff.diff, file_list_view.repository)

      diff.prepare_for_rendering!
    end

    new_tree_entries.compact!
    old_tree_entries.compact!

    # filter out diffs that don't have content
    content_file_views = file_views.select(&:has_content?)
    content_tree_entries = content_file_views.map(&:diff_blob).reject(&:nil?)

    # prefill attributes and line counts
    if !use_better_generated_logic
      TreeEntry.load_attributes!(content_tree_entries, file_list_view.attributes_commit_oid)
    end
    TreeEntry.load_line_counts!(file_list_view.repository, content_tree_entries)

    # prefill syntax highlighted diff
    diff_entries = content_file_views.map(&:diff)
    highlighted_diff = SyntaxHighlightedDiff.new(file_list_view.repository)

    highlighted_diff.highlight!(diff_entries) unless use_styling_directives
    highlighted_diff.highlight_with_styled_directives!(diff_entries) if use_styling_directives

    [file_views, new_tree_entries, old_tree_entries, highlighted_diff]
  end

  def build_file_diff_payload(file_list_view, start_index, current_user, short_path = nil, has_copilot_access: false)
    skip_dependency_review = DependencyReview::ManifestLimitHelper.diff_too_large?(file_list_view)

    use_styling_directives = FeatureFlag.vexi.enabled_or_raise?(:css_custom_highlighting, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    submodule_rendering_enabled = FeatureFlag.vexi.enabled_or_raise?(:diff_submodule_rendering, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    use_better_generated_logic = FeatureFlag.vexi.enabled_or_raise?(:diff_ux_refresh_attribute_prefill, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    file_views, new_tree_entries, old_tree_entries, highlighted_diff = get_prefilled_tree_entries(file_list_view, use_styling_directives: use_styling_directives, use_better_generated_logic: use_better_generated_logic)

    commit_diff = file_list_view.commit.diff
    previous_oid = commit_diff.parsed_sha1
    new_oid = commit_diff.parsed_sha2

    blob_sizes = prepare_blob_sizes(file_list_view.repository, file_list_view.diffs.to_a, has_copilot_access: has_copilot_access)

    file_views.map.with_index do |diff, index|
      current_diff_entry = diff.diff

      if use_styling_directives
        styling_directives = highlighted_diff.styling_directive(current_diff_entry)
      else
        shd = highlighted_diff.colorized_lines(current_diff_entry)
        if shd
          shd.each(&:freeze)
          shd.freeze
        end
      end

      new_tree_entry_temp = new_tree_entries.find { |entry| entry.path == current_diff_entry.b_path }
      old_tree_entry_temp = old_tree_entries.find { |entry| entry.path == current_diff_entry.a_path }
      line_count = diff.blob_line_count
      path_digest = Digest::SHA256.hexdigest(current_diff_entry.path)

      diff_lines = build_diff_line_data(current_diff_entry, shd, styling_directives: styling_directives)

      base_blob_size = blob_sizes[current_diff_entry.a_blob] || 0
      head_blob_size = blob_sizes[current_diff_entry.b_blob] || 0

      copilot_chat_reference = nil
      if has_copilot_access
        copilot_chat_reference = build_copilot_chat_reference(
          current_diff_entry,
          new_tree_entry_temp,
          old_tree_entry_temp,
          path_digest,
          previous_oid,
          new_oid,
          file_list_view.repository,
          base_blob_size,
          head_blob_size
        )
      end
      rich_diff_data = build_rich_diff_data(diff, file_list_view, short_path, skip_dependency_review, new_tree_entry_temp)

      diff_size = if diff.diff.modified?
        (head_blob_size || 0) - (base_blob_size || 0)
      else
        base_blob_size || 0
      end

      # Rich diffs on large commits should be collapsed on initial page load
      contains_rich_diffs_over_virtualization_limit = rich_diff_data[:canToggleRichDiff] && file_views.length > 40

      if submodule_rendering_enabled && current_diff_entry.submodule?
        submodule_loader_data = Diffs::PageData::Submodule::Loader.load(
          diff_entry: current_diff_entry,
          repository: file_list_view.repository,
          current_user: current_user
        )

        if submodule_loader_data.present?
          submodule_payload = Diffs::PageData::Submodule::Payload.call(submodule_loader_data)
        end
      end

      {
        diffLines: diff_lines,
        diffNumber: index + start_index,
        oldOid: previous_oid,
        newOid: new_oid,
        isBinary: current_diff_entry.binary?,
        lineCount: line_count, #adding this here so it can be consumed on the front end without needing to do a staggered deploy in the future
        isSubmodule: current_diff_entry.submodule?,
        isTooBig: current_diff_entry.too_big?,
        collapsed: contains_rich_diffs_over_virtualization_limit,
        **rich_diff_data,
        linesChanged: current_diff_entry.changes,
        newTreeEntry: if new_tree_entry_temp.nil?
                        nil
                      else
                        {
                          mode: new_tree_entry_temp.mode.to_i,
                          path: new_tree_entry_temp.path,
                          lineCount: current_diff_entry.deleted? ? 0 : line_count,
                          isGenerated: diff.generated?,
                        }
                      end,
        oldTreeEntry: if old_tree_entry_temp.nil?
                        nil
                      else
                        {
                          mode: old_tree_entry_temp.mode.to_i,
                          path: old_tree_entry_temp.path,
                          lineCount: current_diff_entry.deleted? ? line_count : 0,
                        }
                      end,
        linesAdded: current_diff_entry.additions,
        linesDeleted: current_diff_entry.deletions,
        path: current_diff_entry.path,
        pathDigest: path_digest,
        status: current_diff_entry.status_label.upcase,
        submodule: submodule_payload&.to_hash,
        deletedSha: current_diff_entry.a_sha,
        truncatedReason: current_diff_entry.truncated_reason,
        copilotChatReference: copilot_chat_reference,
        diffSize: number_to_human_size(diff_size),
      }
    end
  end

  def prepare_blob_sizes(repository, entries, has_copilot_access: false)
    blob_sizes = {}
    oids = []

    entries.each do |diff|
      oids << diff.a_blob << diff.b_blob if should_prepare_blob_size?(diff, repository, has_copilot_access)
    end

    oids.compact!
    oids.uniq!

    if oids.any?
      headers = repository.read_object_headers(oids)

      headers.each_with_index do |obj_header, i|
        oid = oids[i]
        blob_sizes[oid] = obj_header["size"]
      end
    end

    blob_sizes
  end

  def should_prepare_blob_size?(diff, repository, has_copilot_access)
    diff.binary? || (has_copilot_access && !disable_copilot_diff_entry?(diff, repository))
  end

  def build_file_diff_payload_with_file_list(file_list_view, current_user, short_path = nil, has_copilot_access: false)
    # start_index for initial payload is 0
    diff_payload = build_file_diff_payload(file_list_view, 0, current_user, short_path, has_copilot_access: has_copilot_access)

    # if we have more diffs than can be fit in the initial payload, we add the basic info for the rest of the diffs for the file tree
    if diff_payload.length < file_list_view.summary_delta_views.length
      extra_diffs = file_list_view.summary_delta_views.slice(
        diff_payload.length,
        file_list_view.summary_delta_views.length - diff_payload.length
      ).map do |delta|
        {
          path: delta.path,
          status: change_type(delta.delta.status).to_s.upcase,
          pathDigest: Digest::SHA256.hexdigest(delta.path)
        }
      end

      diff_payload.concat(extra_diffs)
    end

    diff_payload
  end

  def build_copilot_chat_reference(
    diff_entry,
    new_tree_entry,
    old_tree_entry,
    path_digest,
    previous_oid,
    new_oid,
    repository,
    base_blob_size,
    head_blob_size
  )
    if disable_copilot_diff_entry?(diff_entry, repository) || [base_blob_size, head_blob_size].max > 1.megabytes
      return nil
    end

    reference_raw_url = ""
    if previous_oid.present? && new_oid.present?
      reference_raw_url = repository_url(repository) + "/raw/" + previous_oid + "/" + diff_entry.path
    end

    {
      type: "file-diff",
      id: "diff-#{path_digest}",
      url: reference_raw_url,
      baseFile: if old_tree_entry.nil?
                  nil
                else
                  {
          type: "file",
          repoID: repository.id,
          repoName: repository.name,
          repoOwner: repository.owner_display_login,
          path: old_tree_entry.path,
          commitOID: previous_oid,
          url: diff_base_blob_url(diff_entry),
          ref: previous_oid,
        }
                end,
      headFile: if new_tree_entry.nil?
                  nil
                else
                  {
          type: "file",
          repoID: repository.id,
          repoName: repository.name,
          repoOwner: repository.owner_display_login,
          path: new_tree_entry.path,
          commitOID: new_oid,
          url: diff_head_blob_url(diff_entry),
          ref: new_oid,
        }
                end,
    }
  end

  def build_rich_diff_data(diff, file_list_view, short_path, skip_dependency_review, new_tree_entry)
    current_diff = diff.diff

    display_rich_diff, is_rich_diff, skip_dependency_review_for_file = determine_rich_diff(current_diff, diff, short_path, skip_dependency_review)

    if display_rich_diff
      if diff.prose_diff?
        diff_html = prose_diff_html(current_diff, file_list_view.repository)
      elsif diff.code_rendering_service.supports_view?
        render_info = rendered_blob(diff, file_list_view, new_tree_entry)
      end
    end

    # if we have a dependency diff, we just generate a path so we can include it in the payload even if it doesn't default to rich diff
    if is_rich_diff && diff.dependency_review_diff?
      dependency_diff_path = Rails.application.routes.url_helpers.dependency_review_rich_diff_path(
        repository: file_list_view.repository,
        user_id: file_list_view.repository.owner_display_login,
        head_sha: current_diff.b_sha,
        base_sha: current_diff.a_sha,
        manifest_path: current_diff.path
      )
    end

    {
      canToggleRichDiff: is_rich_diff && !skip_dependency_review_for_file,
      dependencyDiffPath: dependency_diff_path,
      defaultToRichDiff: display_rich_diff,
      proseDifffHtml: diff_html,
      renderInfo: render_info,
    }
  end

  def build_branch_commit_payload(commit, current_user)
    begin
      tag_names = commit.repository.rpc.tag_contains(commit.oid)
    rescue GitRPC::ObjectMissing
      tag_names = []
    end

    begin
      branch_names = commit.repository.rpc.branch_contains(commit.oid)
    rescue GitRPC::ObjectMissing
      branch_names = []
      GitHub.dogstats.increment("branch_commits.non_existent_commit")
    end

    introductory_pull_request, parent_introductory_pull_request = ::Promise.all([
      commit.async_introductory_pull_request(viewer: current_user),
      commit.async_parent_introductory_pull_request(viewer: current_user),
    ]).sync

    introductory_pulls = [introductory_pull_request, parent_introductory_pull_request].compact

    branches = if branch_names.include?(commit.repository.default_branch)
      [{ branch: commit.repository.default_branch, prs: pull_requests_for_frontend(introductory_pulls, commit.repository) }]
    else
      branch_names.map do |branch|
        open_pull_requests = if commit.repository.feature_enabled?(:commits_by_pr_status)
          commit.repository.pull_requests_as_head.open_pull_requests_by_status.where(head_ref: Git::Ref.safe_ref_name(ref_names: branch_names))
        else
          commit.repository.pull_requests_as_head.open_pulls.where(head_ref: Git::Ref.safe_ref_name(ref_names: branch_names))
        end
        prs = open_pull_requests.select { |pr| pr.head_ref_name == branch }
        prs += introductory_pulls

        { branch: branch, prs: pull_requests_for_frontend(prs, commit.repository) }
      end
    end

    { branches: branches, tags: BranchSorter.new(tag_names).reverse_each.to_a }
  end

  def preload_comment_associations(comments, current_user, current_repository)
    GitHub::PrefillAssociations.prefill_associations(comments, [:user, :repository], available_records: [current_user, current_repository])

    # prefill comment viewer associations
    core_promises =
      comments.flat_map do |comment|
        [
          comment.async_latest_user_content_edit,
          comment.async_viewer_can_read_user_content_edits?(current_user),
          comment.async_minimizable_by?(current_user),
          comment.async_viewer_can_report?(current_user),
          comment.async_viewer_can_report_to_maintainer?(current_user),
          comment.async_viewer_can_block_from_org?(current_user),
          comment.async_viewer_can_unblock_from_org?(current_user),
        ].flatten
      end

    Promise.all(core_promises).sync

    # prefill author associations
    Promise.all(
        comments.map { |comment| CommentAuthorAssociation.new(comment: comment, viewer: current_user).async_to_sym.then { |sym| comment.preload_attr(:author_association_symbol, sym) } }
      ).sync
  end

  def build_commit_comment_payload(commit_comment, current_user, current_repository, cap_filter, prefill_associations: true)
    preload_comment_associations([commit_comment], current_user, current_repository) if prefill_associations

    last_edit = commit_comment.latest_user_content_edit

    if last_edit
      if last_edit.editor
        editor = {
          relayId: last_edit.editor.global_relay_id,
          login: last_edit.editor.display_login,
          url: avatar_url_for(last_edit.editor, 20),
        }
      end

      last_user_content_edit = {
        relayId: last_edit.global_relay_id,
        editor: editor,
        editedAt: last_edit.updated_at,
      }
    end

    {
      id: commit_comment.id,
      relayId: commit_comment.global_relay_id,
      body: commit_comment.body,
      bodyVersion: commit_comment.body_version,
      htmlBody: commit_comment.body_html(context: { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }),
      createdAt: commit_comment.created_at,
      updatedAt: commit_comment.updated_at,
      lastUserContentEdit: last_user_content_edit,
      path: commit_comment.path,
      position: commit_comment.position,
      isHidden: commit_comment.minimized?,
      viewerCanMinimize:  commit_comment.async_minimizable_by?(current_user).sync,
      minimizedReason: commit_comment.minimized_reason,
      viewerCanDelete: commit_comment.async_viewer_can_delete?(current_user).sync,
      viewerCanUpdate: commit_comment.async_viewer_can_update?(current_user).sync,
      viewerCanReport: commit_comment.async_viewer_can_report?(current_user).sync,
      viewerCanReportToMaintainer: commit_comment.async_viewer_can_report_to_maintainer?(current_user).sync,
      viewerCanBlockFromOrg: commit_comment.viewer_can_block_from_org?(current_user),
      viewerCanUnblockFromOrg: commit_comment.viewer_can_unblock_from_org?(current_user),
      viewerDidAuthor: commit_comment.user_id == current_user&.id, # change this to commit author
      urlFragment: commit_comment.url_fragment,
      viewerCanReadUserContentEdits: commit_comment.viewer_can_read_user_content_edits?(current_user),
      viewerCanReact: current_user.present? ? commit_comment.async_viewer_can_react?(current_user).sync : false,
      reactionGroups: reaction_groups(commit_comment, current_user),
      author: {
        id: commit_comment.user.global_relay_id,
        login: commit_comment.user.display_login,
        avatarUrl: commit_comment.user.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420"),
      },
      authorAssociation: commit_comment.author_association_symbol(current_user), # this might need to be changed to commit author association
      threadId: "#{commit_comment.path}::#{commit_comment.position}",
    }
  end

  def build_inline_thread_data(comment_thread)
    return nil unless comment_thread.comments.length > 0

    # for comment markers we only send back the author stack, comment count, and id
    comment_authors = comment_thread.comments.map do |comment|
      {
        id: comment.id,
        author: {
          id: comment.user.global_relay_id,
          login: comment.user.display_login,
          avatarUrl: comment.user.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
        }
      }
    end

    {
      path: comment_thread.path,
      position: comment_thread.position,
      count: comment_thread.comments.length,
      threads: [{
        id: "#{comment_thread.path}::#{comment_thread.position}",
        commentsData: {
          totalCount: comment_thread.comments.length,
          comments: comment_authors,
        },
        # diff controls figure out left/right for additions/deletions
        # this sets the fallback side to use when it's an unchanged line in split view
        diffSide: "RIGHT"
      }]
    }
  end

  def is_subscribed_to_commit(current_user, current_repository, current_commit)
    subscribed = false

    if current_user.present?
      thread_subscription = Notifications::Subscriptions.subscription_status(current_user, current_repository, current_commit)
      repo_subscription = GitHub.newsies.subscription_status(current_user, current_repository)
      subscription_calc = ThreadSubscriptionCalculator.new(current_repository, current_commit, repo_subscription, thread_subscription)
      subscribed = subscription_calc.form_action == :unsubscribe
    end

    subscribed
  end

  def pull_requests_for_frontend(pulls, current_repository)
    return [] unless pulls.present?
    return [] if pulls.empty?

    pulls.map do |pull| {
      number: pull.number,
      showPrefix: show_pr_prefix(pull, current_repository),
      repo: pr_owning_repo(pull, current_repository),
      globalRelayId: pull.global_relay_id
    }
    end
  end

  def reaction_groups(commit_comment, current_user)
    with_database_error_fallback(fallback: []) do
      reaction_users_by_emoji = Hash.new { |h, k| h[k] = [] }

      commit_comment.reactions.map do |reaction|
        reaction_users_by_emoji[reaction.content] << reaction.user
      end

      commit_comment.async_reaction_groups.sync.map do |reaction_group|
        reactive_users = reaction_users_by_emoji[reaction_group.emotion.content] || []
        reaction = {
          content: reaction_group.emotion.platform_enum,
          viewerHasReacted: reactive_users.include?(current_user)
        }

        reactors = reactive_users.map do |reactive_user|
          {
            login: reactive_user.display_login,
            typeName: reactive_user.type
          }
        end

        {
          reaction: reaction,
          reactors: reactors,
          totalCount: reaction_group.total_count
        }
      end
    end
  end

  def show_pr_prefix(pr, current_repository)
    pr.repository_id != current_repository&.id
  end

  def pr_owning_repo(pr, current_repository)
    owning_repo = (pr.repository || current_repository)
    Repos::ReactPayload.current_repository_nwo_payload(owning_repo)
  end

  def determine_rich_diff(current_diff, diff_entry, short_path, skip_dependency_review)
    file_type = get_file_type(current_diff.path)
    diff_short_path = diff_short_path(current_diff)
    match_path = short_path && short_path == diff_short_path

    skip_dependency_review_for_file = skip_dependency_review && diff_entry.dependency_review_diff?

    if current_diff.deleted?
      can_display_rich_diff = false
      default_to_rich_diff = false
    # File mode changed, without a content change
    elsif current_diff.modified? && current_diff.b_blob.nil?
      can_display_rich_diff = false
      default_to_rich_diff = false
    elsif diff_entry.code_rendering_service.supports_view?
      can_display_rich_diff = current_diff.similarity != 100 # 100 means the file content is identical so we don't need to show a rich diff
      default_to_rich_diff = diff_entry.code_rendering_service.default_to_rich_diff_view?
    else # legacy render check and prose diff (Markdown type views)
      can_display_rich_diff = true
      default_to_rich_diff = ((current_diff.binary? || file_type == ".svg") && diff_entry.supports_rich_diff?)
    end

    should_display_rich_diff = (
      !skip_dependency_review_for_file && match_path || default_to_rich_diff
    )

    # If we can display a rich diff and it is the default, we should show the rich diff
    display_rich_diff = can_display_rich_diff && should_display_rich_diff
    is_rich_diff = !skip_dependency_review_for_file && can_display_rich_diff && diff_entry.toggleable?

    [display_rich_diff, is_rich_diff, skip_dependency_review_for_file]
  end

  def prose_diff_html(diff, repository)
    if diff.added?
      before_html = ActiveSupport::SafeBuffer.new("")
    else
      before_blob_data = before_blob(diff, repository)
      if before_blob_data
        before_html = with_failbot_rescue("gh.repo.path": diff.path, "gh.diff.type": "before_html") do
          markup_blob_content_if_successful(before_blob_data, path: before_blob_data.path, sanitize_orphan_hrefs: true)
        end
      end
    end

    if diff.deleted?
      after_html = ActiveSupport::SafeBuffer.new("")
    else
      after_blob_data = after_blob(diff, repository)
      if after_blob_data
        after_html = with_failbot_rescue("gh.repo.path": diff.path, "gh.diff.type": "after_html") do
          markup_blob_content_if_successful(after_blob_data, path: after_blob_data.path, sanitize_orphan_hrefs: true)
        end
      end
    end

    if before_html && after_html
      html_diff = with_failbot_rescue("gh.repo.path": diff.path, "gh.diff.type": "@html_diff") do
        GitHub.instrument "prose-diff.render", diff: diff, repository: repository do
          GitHub::HTML::Diff.new(before_html, after_html)
        end
      end
    end

    if html_diff
      html = with_failbot_rescue("gh.repo.path": diff.path, "gh.diff.type": "diff_html") do
        formatted_blob_content(html_diff.html)
      end
    end

    html
  end

  def rendered_blob(file_view, file_list_view, new_tree_entry)
    {
      url: file_view.code_rendering_service.rich_diff_url(file_view: file_view, file_list_view: file_list_view),
      type:  file_view.code_rendering_service.render_type,
      identityUuid: file_view.code_rendering_service.identity,
      size: new_tree_entry.size.to_i,
    }
  end

  def before_blob(diff, repository)
    return if diff.a_blob.nil?

    tree_entry = TreeEntry.load(repository, {
      "oid" => diff.a_blob,
      "path" => diff.a_path,
      "mode" => diff.a_mode,
      "type" => "blob",
    })

    tree_entry.data ? tree_entry : nil
  end

  def after_blob(diff, repository)
    return if diff.b_blob.nil?

    tree_entry = TreeEntry.load(repository, {
      "oid" => diff.b_blob,
      "path" => diff.b_path,
      "mode" => diff.b_mode,
      "type" => "blob",
    })

    tree_entry.data ? tree_entry : nil
  end

  def with_failbot_rescue(additional = {})
    yield
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    failbot(e, { app: "github-diff" }.merge(additional))
    nil
  end

  ALLOWED_DIFF_JSON_FIELDS = [:diffLines,
    :diffNumber,
    :diffSize,
    :isBinary,
    :isTooBig,
    :collapsed,
    :isSubmodule,
    :lineCount,
    :linesChanged,
    :newTreeEntry,
    :oldTreeEntry,
    :styleDirectives,
    :stylingDirective,
    :c, :s, :e,
    :linesAdded,
    :linesDeleted,
    :path,
    :pathDigest,
    :status,
    :truncatedReason,
    :type,
    :blobLineNumber,
    :text,
    :html,
    :rawUrl,
    :size,
    :isLfsPointer,
    :displayNoNewLineWarning,
    :position,
    :left,
    :oldOid,
    :newOid,
    :copilotChatReference,
    :baseFile,
    :headFile,
    :repoID,
    :repoName,
    :repoOwner,
    :commitOID,
    :ref,
    :right,
    :mode,
    :path,
    :lineCount,
    :threadsData,
    :threads,
    :id,
    :line,
    :commentsData,
    :totalCount,
    :comments,
    :author,
    :id,
    :login,
    :deletedSha,
    :avatarUrl,
    :diffSide,
    :isGenerated,
    :canToggleRichDiff,
    :defaultToRichDiff,
    :proseDifffHtml,
    :renderInfo,
    :url,
    :type,
    :identityUuid,
    :size,
    :dependencyDiffPath,
    :submodule,
    :summary,
    :changedFiles,
    :basePath,
    :contentsUrl,
    :submoduleUrl,
    :oldCommitOid,
    :newCommitOid,
  ]
end
