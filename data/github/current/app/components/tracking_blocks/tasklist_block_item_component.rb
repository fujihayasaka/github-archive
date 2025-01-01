# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class TasklistBlockItemComponent < ApplicationComponent
    extend T::Sig
    include LabelsHelper
    include HydroHelper
    include GitHub::Goomba::Reference::Helpers

    attr_reader(
      :title,
      :state,
      :owner_login,
      :repository_id,
      :repository_name,
      :display_number,
      :state_reason,
      :url,
      :uuid,
      :item_id,
      :tasklist_block_id,
      :readonly,
      :current_viewer_write_access,
      :checked,
      :render_context,
      :current_user,
      :position,
      :title_html,
      :completion,
      :item_type,
      :repository,
      :parent_issue,
      :error,
      :tracked_by_title
    )

    alias readonly? readonly
    alias current_viewer_write_access? current_viewer_write_access
    alias owner_display_login owner_login

    # title: item title
    #
    # repository_name: item repository canonical name
    #
    # owner_login: repository owner login
    #
    # display_number: item display number
    #
    # state: item state
    #   - Issue: "draft", "draftClosed", "open", "closed", "merged"
    #
    # state_reason: string with the reason of the state
    #   - Issue: "not_planned"
    #
    # url: dotcom url to navigate to the item
    #
    # uuid: issues-graph item uuid
    #
    # item_id: dotcom db item id
    #
    # tasklist_block_id: issues-graph tasklist block uuid, or tasklist block position if created pre-cache.
    #
    # readonly: used for checkbox at the moment. Soon to be removed
    #
    # current_viewer_write_access: if user can write to the repository
    #
    # render_context: a RenderContextItem instance with all relevant information to properly rendering the item
    #
    # current_user: currently logged-in user
    #
    sig do
      params(
        title: String,
        state: String,
        owner_login: T.nilable(String),
        repository_id: T.nilable(Integer),
        repository_name: T.nilable(String),
        display_number: T.nilable(Integer),
        state_reason: T.nilable(String),
        url: T.nilable(String),
        uuid: T.nilable(T.any(String, Integer)),
        item_id: T.nilable(Integer),
        tasklist_block_id: T.nilable(T.any(String, Integer)),
        readonly: T::Boolean,
        current_viewer_write_access: T::Boolean,
        assignees: T.untyped,
        labels: T.untyped,
        completion: T.nilable(Hash),
        checked: T::Boolean,
        render_context: T.nilable(TrackingBlocks::RenderContextItem),
        current_user: T.nilable(User),
        position: T.nilable(Integer),
        title_html: T.nilable(String),
        item_type: T.nilable(Symbol),
        repository: T.nilable(Repository),
        parent_issue: T.nilable(::Issue),
        error: T.nilable(String),
        tracked_by_title: T.nilable(String),
      )
      .void
    end
    def initialize(
        title:,
        state:,
        owner_login: nil,
        repository_id: nil,
        repository_name: nil,
        display_number: nil,
        state_reason: nil,
        url: nil,
        uuid: nil,
        item_id: nil,
        tasklist_block_id: nil,
        readonly: false,
        current_viewer_write_access: false,
        assignees: [],
        labels: [],
        completion: nil,
        checked: false,
        render_context: nil,
        current_user: nil,
        position: nil,
        title_html: nil,
        item_type: nil,
        repository: nil,
        parent_issue: nil,
        error: nil,
        tracked_by_title: nil
      )
      @title = title
      @owner_login = owner_login
      @repository_id = repository_id
      @repository_name = repository_name
      @display_number = display_number
      @state = state
      @state_reason = state_reason
      @url = url
      @uuid = uuid.to_s
      @item_id = item_id
      @tasklist_block_id = tasklist_block_id.to_s
      @readonly = readonly
      @current_viewer_write_access = current_viewer_write_access
      @render_context = render_context.nil? ? TrackingBlocks::RenderContextItem.new : render_context
      @assignees = assignees
      @labels = labels
      @completion = completion
      @current_user = current_user
      @position = position
      @title_html = title_html
      @item_type = item_type
      @repository = repository
      @parent_issue = parent_issue
      @error = error
      @tracked_by_title = tracked_by_title
    end

    def is_precache?
      GitHub.flipper[:tasklist_block_precache].enabled?(@render_context.current_repository_owner)
    end

    def draft_issue?
      is_draft_item_type = @item_type.nil? || @item_type == :UNDEFINED || @item_type == TrackingBlocks::DraftIssue::ITEM_TYPE.to_sym
      is_draft_state = [TasklistBlocks::DraftIssueState::OPEN, TasklistBlocks::DraftIssueState::CLOSED].include?(@state)
      is_draft_item_type && is_draft_state
    end

    def pull_request?
      @item_type == PullRequest::IssuesGraphDependency::ITEM_TYPE.to_sym
    end

    def get_turbo_src(menu_type)
      tracking_block_menu_path(@owner_login, @repository_name, @item_id, @tasklist_block_id, menu_type)
    end

    def aria_item_label
      if draft_issue?
        task_state = @state == TasklistBlocks::DraftIssueState::CLOSED ? "Completed" : "Open"
        task_toggle = @state == TasklistBlocks::DraftIssueState::CLOSED ? "to do" : "done"

        "#{task_state} task. #{@title}."
      else
        task_state = @state == TasklistBlocks::IssueState::CLOSED ? "Completed" : "Open"

        assignee_string = if assignees.any?
          assignees.length == 1 ? ", assigned to #{assignees.first.login}" : ", #{assignees.length} assignees" # rubocop:disable GitHub/DoNotAllowLogin
        else
          ""
        end

        label_string = if labels.any?
          labels.length == 1 ? ", label #{labels.first.name}" : ", #{labels.length} labels"
        else
          ""
        end

        "#{task_state} issue #{@title} #{@repository_name} #{@item_id}#{assignee_string}#{label_string}. You are on a link."
      end
    end

    def checked?
      @state == TasklistBlocks::DraftIssueState::CLOSED
    end

    def safe_title
      title_html.presence || title
    end

    def labels
      @labels.uniq.compact.sort_by(&:name)
    end

    def assignees
      # Proto issues still use `login` so we disable this rubocop rule
      @assignees.uniq.compact.sort_by(&:login) # rubocop:disable GitHub/DoNotAllowLogin
    end

    def show_metadata_edit_menu?
      is_draft = draft_issue? || @item_id.nil? || @item_id.zero?
      # If precache, we don't have direct access to current_viewer permissions
      # so omit that from this return value, and check using authz wrapper instead
      user_cannot_write = !is_precache? && !current_viewer_write_access?
      true unless is_draft || user_cannot_write
    end

    def metadata_edit_menu_label
      if draft_issue?
        "Options"
      else
        "Edit..."
      end
    end

    def issue_click_hydro_event
      hydro_event = "tasklist.item.link_click"
      hydro_event_setup = hydro_click_tracking_attributes(hydro_event, {
        link_type: pull_request? ? "pull_request" : "issue",
        repository_id: repository_id,
        child_url: url,
      })
    end

    def edit_action(type)
      actions = {
        assignee: "click:tracking-block#handleEditAssignees",
        label: "click:tracking-block#handleEditLabels",
        project: "click:tracking-block#handleEditProject",
      }

      if is_precache? && @repository
        repository_reference_wrapper(@repository, check_type: :push) do |wrapper|
          wrapper.authorized do
            return actions[type] if show_metadata_edit_menu?
          end
          wrapper.unauthorized { "" }
        end
      end

      return actions[type] if show_metadata_edit_menu?
      ""
    end
  end
end
