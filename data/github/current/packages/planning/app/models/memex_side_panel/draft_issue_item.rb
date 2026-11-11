# typed: true
# frozen_string_literal: true

class MemexSidePanel::DraftIssueItem < MemexSidePanel::Item

  sig do
    params(
     project_item_id: T.any(Integer, String),
     memex_project: MemexProject,
     current_user: T.nilable(User)
   ).void
  end
  def initialize(project_item_id, memex_project:, current_user:)
    super(memex_project, current_user: current_user)
    @item = T.let(
      memex_project.memex_project_items.is_draft.find_by(id: project_item_id),
      T.nilable(MemexProjectItem)
    )
    draft_issue = T.cast(@item&.content, T.nilable(DraftIssue))
    @draft_issue = draft_issue
  end

  # include omit_comments to adhere to the interface
  def show(omit_comments: false, omit_capabilities: false)
    raise NotFoundError unless (item = self.item)
    raise NotFoundError unless (draft_issue = self.draft_issue)

    draft_issue.set_current_user(current_user)
    fields = draft_issue.memex_content_hash(fields: [:body, :body_html, :created_at, :updated_at, :user])
    title_value = item.memex_denormalized_title_value

    result = {
      itemKey: {
        kind: "project_draft_issue",
        projectItemId: item.id
      },
      title: title_value[:title],
      description: {
        body: fields[:body],
        bodyHtml: fields[:body_html],
        # Draft issues don't keep track of specifically body edits, so just used updated_at
        editedAt: item[:updated_at]
      },
      createdAt: item[:created_at],
      updatedAt: item[:updated_at],
      user: {
        login: fields[:user][:login],
        id: fields[:user][:id],
        avatarUrl: fields[:user][:avatar_url],
        htmlUrl: fields[:user][:url],
      },
      state: {
        state: "draft"
      },
      assignees: draft_issue.assignees.map { |assignee| assignee.memex_project_column_value.to_hash },
      projectItemId: item.id,
      liveUpdateChannel: this_memex.live_updates_channel,
    }

    unless omit_capabilities
      capabilities = []
      capabilities += %w[editTitle editDescription] if this_memex.viewer_can_write?(current_user)
      result[:capabilities] = capabilities
    end

    result
  end

  def update(update)
    raise NotFoundError unless (item = self.item)
    raise NotFoundError unless (draft_issue = self.draft_issue)

    # We should allow the body to be updated to be empty, so check if it's nil instead of present
    if !update[:body].nil?
      raise NotFoundError unless item.content
      unless this_memex.viewer_can_write?(current_user)
        raise PermissionError, "User does not have permission to write to memex"
      end

      draft_issue.update!(body: update[:body])
    elsif update[:title].present?
      unless this_memex.viewer_can_write?(current_user)
        raise PermissionError, "User does not have permission to write to memex"
      end

      column_to_update = this_memex.find_column_by_name_or_id("Title")
      item.set_column_value(column_to_update, { title: update[:title] }, T.must(current_user), skip_elasticsearch_updates: false)
    elsif !update[:assignees].nil?
      unless this_memex.viewer_can_write?(current_user)
        raise PermissionError, "User does not have permission to update this draft issue\'s assignees"
      end

      column_to_update = this_memex.find_column_by_name_or_id("Assignees")
      item.set_column_value(column_to_update, update[:assignees].reject(&:empty?).map(&:to_i), T.must(current_user), skip_elasticsearch_updates: false)
    else
      raise InvalidParamsError, "Update must contain at least one of `body` or `title`"
    end

    item.reload
    show
  end

  def suggestions_target(suggestion_type)
    can_suggest = case suggestion_type
    when "assignees"
      this_memex.viewer_can_write?(current_user)
    else
      raise InvalidParamsError, "Suggestion type must be `assignees`"
    end

    raise NotFoundError unless item
    unless can_suggest
      raise PermissionError, "User does not have permission to get suggestions for #{suggestion_type}"
    end

    T.must(item).content
  end

  def resource_for_conditional_access
    this_memex
  end

  def target_for_conditional_access
    this_memex.target_for_conditional_access
  end

  def viewer_can_read?
    item && this_memex.viewer_can_read?(current_user)
  end

  def viewer_can_update?
    item && this_memex.viewer_can_write?(current_user)
  end

  private

  sig { returns(T.nilable(MemexProjectItem)) }
  attr_reader :item

  sig { returns(T.nilable(DraftIssue)) }
  attr_reader :draft_issue
end
