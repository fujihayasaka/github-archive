# typed: true
# frozen_string_literal: true

class MemexSidePanel::IssueItem < MemexSidePanel::Item
  include GitHub::Tracing

  trace_method(
    :show,
    span_name: "side_panel_issue_item/show",
    span_annotator: ->(_redactor, span, _context, result) do
      span.add_attributes({
        "gh.memex.side_panel_issue_item.included_comments" => result[:comments]&.present?,
        "gh.memex.side_panel_issue_item.number_of_comments" => result[:comments]&.length,
        "gh.memex.side_panel_issue_item.included_capabilities" => result[:capabilities]&.present?
      }.compact)
    end
  )

  trace_method(
    :fetch_comments,
    span_name: "side_panel_issue_item/fetch_comments",
    span_annotator: ->(_redactor, span, _context, result) do
      span.add_attributes({
        "gh.memex.side_panel_issue_item.number_of_comments" => result.length,
      }.compact)
    end
  )

  trace_method(:fetch_capabilities, span_name: "side_panel_issue_item/fetch_capabilities")

  sig do
    params(
      item_id: T.any(String, Integer),
      repository_id: T.any(String, Integer),
      memex_project: MemexProject,
      current_user: T.nilable(User),
      cap_filter: ConditionalAccess::Web::Filter
    ).void
  end
  def initialize(item_id, repository_id:, memex_project:, current_user:, cap_filter:)
    super(memex_project, current_user: current_user)
    @cap_filter = cap_filter

    load_item(item_id, repository_id)
  end

  sig { returns(T.nilable(Issue)) }
  attr_reader :item

  def show(omit_comments:, omit_capabilities:)
    show_item(omit_comments: omit_comments, omit_capabilities: omit_capabilities)
  end

  def suggestions_target(suggestion_type)
    return unless item
    item = T.must(self.item)

    can_suggest = case suggestion_type
    when "assignees"
      item.assignable_by?(actor: current_user)
    when "labels"
      item.labelable_by?(actor: current_user)
    when "milestones"
      item.can_set_milestone?(current_user)
    else
      raise InvalidParamsError, "Suggestion type must be `assignees`, `labels`, or `milestones`"
    end

    unless can_suggest
      raise PermissionError, "User does not have permission to get suggestions for #{suggestion_type}"
    end

    item
  end

  def comment(comment, update_state: "", state_reason: nil)
    return unless item
    item = T.must(self.item)

    unless item.can_comment?(current_user)
      raise PermissionError, "User does not have permission to comment on this issue"
    end

    created_comment = if update_state == "closed"
      item.comment_and_close(current_user, comment, state_reason)
    elsif update_state == "open"
      item.comment_and_open(current_user, comment)
    else
      item.create_comment(current_user, comment)
    end

    serialize_comment(created_comment)
  end

  def edit_comment(comment_id, body)
    return false unless item

    item = T.must(self.item)
    comment = IssueComment.find_by(id: comment_id, issue_id: item.id)

    raise NotFoundError, "Comment not found" unless comment
    unless comment.async_editable_by?(current_user).sync
      raise PermissionError, "User does not have permission to edit this comment"
    end

    saved = comment.update_body(body, current_user)
    return false unless saved

    serialize_comment(comment.reload)
  end

  def update_reaction(command, reaction, comment_id:)
    return unless item

    item = T.must(self.item)
    subject = item
    subject = IssueComment.find_by(id: comment_id, issue_id: item.id) if comment_id
    unless subject&.viewer_can_react?(current_user)
      raise PermissionError, "User does not have permission to react to this item"
    end

    if command == "react"
      subject.react(actor: current_user, content: reaction)
    elsif command == "unreact"
      subject.unreact(actor: current_user, content: reaction)
    else
      raise UnsupportedError, "Unsupported reaction command #{command}"
    end
  end

  def update_state(state, state_reason: nil)
    return unless item

    item = T.must(self.item)
    if state == "closed"
      item.close(current_user, attributes: { state_reason: state_reason })
    elsif state == "open"
      item.reopen!(current_user)
    else
      false
    end
  end

  def update(update)
    return unless item
    item = T.must(self.item)

    # We should allow the body to be updated to be empty, so check if it's nil instead of present
    if !update[:body].nil?
      unless item.viewer_can_update?(current_user)
        raise PermissionError, "User does not have permission to edit this issue"
      end

      item.update_body(update[:body], current_user)
    elsif update[:title].present?
      unless item.viewer_can_update?(current_user)
        raise PermissionError, "User does not have permission to update this issue title"
      end

      item.update({ title: update[:title] })
    elsif !update[:labels].nil?
      unless item.labelable_by?(actor: current_user)
        raise PermissionError, "User does not have permission to update this issue label"
      end

      label_ids = update[:labels].reject(&:empty?).map(&:to_i)
      labels_to_update = repository.labels.where(id: label_ids)
      item.replace_labels(labels_to_update)
    elsif !update[:assignees].nil?
      unless item.assignable_by?(actor: current_user)
        raise PermissionError, "User does not have permission to update this issue assignees"
      end

      assignee_ids = update[:assignees].reject(&:empty?).map(&:to_i)
      item.assignees = User.where(id: assignee_ids)
    elsif !update[:milestone].nil?
      unless item.can_set_milestone?(current_user)
        raise PermissionError, "User does not have permission to update this issue\'s milestone"
      end

      milestone_to_update = repository.milestones.find(update[:milestone]) unless update[:milestone] == "clear"
      item.update({ milestone: milestone_to_update })
    else
      raise InvalidParamsError, "Update must contain at least one of `body` or `title`"
    end

    load_item(item.id, item.repository_id)

    show_item(omit_comments: true, omit_capabilities: true)
  end

  # cap_audit:to_fix - It is somewhat unusual to default to `:no_resource_for_conditional_access` for a model implementing `resource_for_conditional_access`.
  # Under what conditions could item be nil? And, in those cases, are we sure it is okay to bypass CAP?
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless item # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    item
  end

  # cap_audit:to_fix - It is somewhat unusual to default to `:no_target_for_conditional_access` for a model implementing `target_for_conditional_access`.
  # Under what conditions could item be nil? And, in those cases, are we sure it is okay to bypass CAP?
  # Also, I think TFCA may be unncessary here because RFCA is implemented.
  def target_for_conditional_access
    return :no_target_for_conditional_access unless item # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    T.must(item).target_for_conditional_access
  end

  def viewer_can_read?
    return false unless item

    user = current_user

    item = T.must(self.item)

    return false if user.present? && item.hide_from_user?(user)

    item.readable_by?(user)
  end

  def viewer_can_update?
    authorization = Issues::ContentAuthorizer.new(current_user, "update", repo: repository)
    authorization.passed?
  end

  private

  sig { returns(ConditionalAccess::Web::Filter) }
  attr_reader :cap_filter

  def show_item(omit_comments: false, omit_capabilities: false)
    return unless item

    item = T.must(self.item)
    item.strict_loading!
    memex_item = this_memex.memex_project_items.find_by(content_id: item.id, content_type: Issue.name)

    labels = item.labels
    Issue::Loader::Base.new.async_preload_attribute(
      labels,
      :preloaded_name_html,
      :async_name_html
    ).sync

    body = if TasklistBlocks::UrlExpander.enabled?(item)
      TasklistBlocks::UrlExpander.expand(item)
    else
      item.body
    end

    tracked_by = TasklistBlocks::Redactor.new(
        viewer: current_user,
        issues: item.parent_issues,
        cap_filter: cap_filter,
        options: { exclude_redacted_issues: true },
      ).issues.map { |i| i.to_h.deep_transform_keys { |key| key.to_s.camelize(:lower) }.as_json }

    HierarchyCommands::Preload.new(
      issue: item,
      repository: repository,
      owner: repository.owner,
      viewer: current_user
    ).call

    issue = {
      itemKey: {
        kind: "issue",
        itemId: item.id,
        repositoryId: item.repository_id,
        # TODO: remove once this is no longer being used by the front-end
        repoId: item.repository_id
      },
      title: {
        raw: item.title,
        html: GitHub::Goomba::TitleMarkdownFilter.call(item.title)
      },
      description: {
        body: body,
        bodyHtml: item.body_html(context: {
          viewer: current_user,
          cap_filter: cap_filter,
          unfurl_references: true,
        }),
        editedAt: item.edited_at
      },
      url: item.url,
      createdAt: item.created_at,
      updatedAt: item.updated_at,
      user: serialize_user(item.user),
      state: {
        state: item.state,
        stateReason: item.state_reason
      },
      reactions: item.prelude_user_logins_by_reaction,
      labels: labels.map { |label| label.memex_column_hash },
      assignees: item.assignees.map { |assignee| assignee.memex_column_hash },
      repositoryName: repository.name,
      issueNumber: item.number,
      milestone: item.milestone&.memex_column_hash,
      projectItemId: memex_item&.id,
      completion: maybe_completion
    }

    issue[:liveUpdateChannel] = GitHub::WebSocket.signed_channel(GitHub::WebSocket::Channels.issue(item))
    issue[:comments] = fetch_comments unless omit_comments
    issue[:capabilities] = fetch_capabilities unless omit_capabilities
    issue[:repository] = repository.memex_column_hash
    issue[:slashCommandsSubjectGid] = SlashCommands.subject_gid(item) if slash_commands_enabled?
    issue[:trackedBy] = tracked_by unless tracked_by.nil?

    issue
  end

  def slash_commands_enabled?
    SlashCommands.enabled_for?(current_user, repository)
  end

  def maybe_completion
    return unless item

    completion = T.must(item).hierarchy_completion
    return unless completion

    {
      completed: completion.completed,
      total: completion.total,
      percent: completion.percent,
    }
  end

  def fetch_comments
    return unless item

    item = T.must(self.item)

    GitHub.dogstats.time("memex_side_panel_item.comments") do
      # TODO: we'll likely need to paginate this in some form or another
      comments = item.comments.filter_spam_for(current_user)
      GitHub::PrefillAssociations.prefill_batch_method(comments, :prelude_user_logins_by_reaction)
      GitHub::PrefillAssociations.prefill_batch_method(comments, :prelude_viewer_can_react, current_user)

      promises = [
        Issue::Loader::Base.new.async_preload_attribute(
          comments,
          :body_html,
          :async_body_html,
          [],
          { context: {
            viewer: current_user,
            unfurl_references: true,
            cap_filter: cap_filter } }
        ),
        Issue::Loader::Base.new.async_preload_attribute(comments, :viewer_can_update, :async_viewer_can_update?,
          [current_user])
        # TODO: Perhaps this should be abstracted as part of `AuthorAssociable`? You can find a similar preloading
        # in PRs and commit comment implementations
      ]
      promises += comments.map do |associable|
        CommentAuthorAssociation.new(comment: associable, viewer: current_user).async_to_sym.then do |sym|
          associable.preload_attr(:author_association_symbol, sym)
        end
      end

      Promise.all(promises).sync

      comments.map { |comment| serialize_comment(comment) }
    end
  end

  def fetch_capabilities
    return unless item
    item = T.must(self.item)

    GitHub.dogstats.time("memex_side_panel_item.capabilities") do
      Promise.all([
        item.async_viewer_can_update?(current_user).then { |pushable| pushable ? ["editTitle"] : [] },
        item.async_editable_by?(current_user).then { |editable| editable ? ["editDescription"] : [] },
        item.async_viewer_can_react?(current_user).then { |reactable| reactable ? ["react"] : [] },
        item.async_can_comment?(current_user).then { |commentable| commentable ? ["comment"] : [] },
        item.async_closable_by?(current_user).then { |closable| closable ? ["close"] : [] },
        item.reopenable_by?(current_user) ? ["reopen"] : [],
      ]).sync.flatten
    end
  end

  sig do
    params(
      id: T.nilable(T.any(String, Integer)),
      repository_id: T.nilable(T.any(String, Integer))
    ).returns(T.nilable(Issue))
  end
  def load_item(id, repository_id)
    return unless id.present? && repository_id.present?
    @item = Issue
      # Preload now so we can use #strict_loading! to ensure we avoid n+1 queries later:
      .includes(:user, :repository, :assignees, :milestone, labels: :repository)
      .find_by(id: id, repository_id: repository_id)

    if @item
      # Compute this required field by properly traversing the `latest_user_content_edit` association
      #
      # We cannot do this within the `includes` call above because this will query for all user_content_edits
      # for the issue, may return hundreds of records and exceed the resource limits in the vitess infrastructure
      # that sits in front of the cluster
      edited_at = @item.edited_at
    end

    @item
  end

  delegate :repository, to: :item

  def serialize_comment(comment)
    return if comment.nil?

    capabilities = []
    capabilities.push("editDescription") if comment.viewer_can_update?(current_user)
    capabilities.push("react") if comment.prelude_viewer_can_react(current_user)

    {
      id: comment.id,
      createdAt: comment.created_at,
      updatedAt: comment.updated_at,
      description: {
        bodyHtml: comment.body_html(context: {
          viewer: current_user,
          cap_filter: cap_filter,
          unfurl_references: true,
        }),
        body: comment.compressed_body,
        editedAt: comment.edited_at
      },
      issueId: comment.issue_id,
      repositoryId: comment.repository_id,
      user: serialize_user(comment.user),
      authorAssociation: repository.private? ? nil : comment.author_association_symbol(current_user),
      capabilities: capabilities,
      reactions: comment.prelude_user_logins_by_reaction,
    }
  end

  def serialize_user(user)
    # handle the case where the author of the issue or issue comment
    # has deleted their account
    user ||= User.ghost

    {
      login: user.display_login,
      id: user.id,
      avatarUrl: user.primary_avatar_url(40),
      htmlUrl: user.permalink,
      type: user.user_type,
    }
  end
end
