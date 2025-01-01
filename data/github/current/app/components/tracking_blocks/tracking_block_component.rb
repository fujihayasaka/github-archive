# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class TrackingBlockComponent < ApplicationComponent
    include GitHub::Goomba::Reference::Helpers
    include HydroHelper

    DEFAULT_HEADING_LEVEL = 3
    # Pattern used for matching tasklist title
    TASKLIST_TITLE_SELECTOR = /(^#*) #{TaskList::Filter::IssueTextPattern}/

    EMPLOYEE_FEEDBACK_URL = "https://github.com/github/memex/discussions/13507"
    PUBLIC_FEEDBACK_URL = "https://github.com/community/community/discussions/39106"

    attr_reader :id,
                :title,
                :title_html,
                :heading_level,
                :validation_msg,
                :items,
                :current_user,
                :render_context,
                :items_render_context,
                :hierarchy_completion,
                :hierarchy_query_type,
                :tasklist_block_markdown_at_rest_enabled,
                :tasklist_block_hard_limits_enabled,
                :hierarchy_response_source_type,
                :repository,
                :parent_issue,
                :options

    # id: tracking block uuid, or tracking block position if created pre-cache. (Can be omitted when generating a preview)
    #
    # title (optional): string with the title of the tracking block
    #
    # heading_level (optional): The Markdown header level the user used to generate the tracking block
    #
    # items: the tracking block required list of hash item
    #
    # readonly: can be forced to true. Otherwise, it will be calculated based on the render_context
    #
    # render_context: a RenderContextBlock instance with all relevant information to properly rendering the tracking block

    def initialize(
      id: nil,
      title: nil,
      title_html: nil,
      validation_msg: nil,
      heading_level: DEFAULT_HEADING_LEVEL,
      items: nil,
      readonly: false,
      render_context:,
      hierarchy_completion: nil,
      hierarchy_query_type: nil,
      hierarchy_response_source_type: nil,
      current_user: nil,
      repository: nil,
      parent_issue: nil,
      options: {}
    )
      @id = id.to_s
      @items = items&.sort_by { |item| (item[:position] || 0).to_i }

      @title = title
      @title_html = title_html
      @validation_msg = validation_msg&.to_sym
      @heading_level = heading_level.clamp(1, 6)
      @readonly = readonly

      @current_user = current_user
      @repository = repository
      @parent_issue = parent_issue

      @render_context = render_context
      @items_render_context = TrackingBlocks::RenderContextItem.new(
        current_owner_login: @render_context.current_owner_login,
        current_repository_name: @render_context.current_repository_name,
        current_repository_owner: @render_context.current_repository_owner
      )

      @hierarchy_completion = hierarchy_completion
      @hierarchy_query_type = hierarchy_query_type
      @hierarchy_response_source_type = hierarchy_response_source_type

      @options = options
      @tasklist_block_markdown_at_rest_enabled = options.fetch(:tasklist_block_markdown_at_rest_enabled, false)
      @tasklist_block_hard_limits_enabled = options.fetch(:tasklist_block_hard_limits_enabled, false)
    end

    def is_precache?
      GitHub.flipper[:tasklist_block_precache].enabled?(render_context.current_repository_owner)
    end

    def render?
      return true if is_precache?
      !@items.nil?
    end

    def readonly?
      return @readonly if is_precache?
      @readonly || !@render_context.current_viewer_can_update || is_readonly_validation_msg?
    end

    def is_completed?
      # TODO: The completion icon with precache for the tasklist itself is controlled by which checkboxes are checked.
      # This will not be accurate accurate if the tasklist contains non-draft items.
      if is_precache?
        return false if content.blank?
        return !content.lines.reject(&:blank?).any? { |line| line.match? TaskList::Filter::IncompleteItemPattern }
      end

      return false if @items.nil?
      return false if @items.empty?
      @items.all? { |item| item[:state] == TasklistBlocks::DraftIssueState::CLOSED || item[:state] == "closed" || item[:state] == TasklistBlocks::PullRequestState::MERGED }
    end

    def title_tag
      :"h#{@heading_level}"
    end

    def trimmed_title
      return nil unless title
      if matches = title.match(TASKLIST_TITLE_SELECTOR)
        return matches[2]
      end
      title
    end

    def safe_title
      @title_html.presence || trimmed_title.presence || TasklistBlocks::TasklistBlock::DEFAULT_NAME
    end

    def form_tracking_block_update_endpoint
      return "" if readonly?

      if @tasklist_block_markdown_at_rest_enabled
        "/#{owner_display_login}/#{repository_name}/issues/#{item_number}"
      else
        "/#{owner_display_login}/#{repository_name}/issues/#{item_number}/tracking_block"
      end
    end

    def feedback_url
      if @current_user&.employee? && GitHub.dotcom_request?
        EMPLOYEE_FEEDBACK_URL
      else
        PUBLIC_FEEDBACK_URL
      end
    end

    def feedback_link(url)
      render(Primer::Beta::Link.new(
        href: url,
        muted: true,
        ml: 2,
        mr: 4,
        style: "margin-bottom: 2px; white-space: nowrap;",
        target: "_blank"
      )) { "Give feedback" }
    end

    def deprecation_notice_message
      link = if @current_user&.employee?
        render(Primer::Beta::Link.new(
          href: "https://github.com/github/sub-issues/discussions/671",
          target: "_blank"
        )) { "internal discussion" }
      else
        render(Primer::Beta::Link.new(
          href: "https://github.blog/changelog/2025-02-18-github-issues-projects-february-18th-update/#tasklist-blocks-will-be-retired-and-replaced-with-sub-issues",
          target: "_blank"
        )) { "Changelog" }
      end

      # We know this is safe because we generate the full countent ourselves
      "We encourage you to migrate your issue tasklist items to sub-issues. Learn more in our #{link}.".html_safe # rubocop:disable Rails/OutputSafety
    end

    def hierarchy_hydro_click_tracking_attributes(tasklist_block_id:, actor:, action:)
      hydro_click_tracking_attributes("tasklist_block.user_action", {
        action: action,
        user_id: actor&.id,
        tasklist_block_id: tasklist_block_id,
      })
    end

    def disable_add_tasks_button?
      return false unless @tasklist_block_hard_limits_enabled
      validation_msg == :hard_limit_tasks_per_tasklist
    end

    private

    def owner_display_login
      @render_context.current_owner_login
    end

    def repository_name
      @render_context.current_repository_name
    end

    def item_number
      @render_context.current_item_display_number
    end

    def show_sunset_banner?
      GitHub.issues_graph_api_deprecated?(@current_user)
    end

    # Used to determine if the validation_msg should disable editing for tasklists UI
    # If editing is allowed the validation_msg, add validation_msg to `validations_viewer_can_update`
    def is_readonly_validation_msg?
      # Editing for tasklists allowed with these validation messages
      validations_viewer_can_update = [
        :legacy_tasklist,
        :soft_limit_tasks_per_tasklist,
        :soft_limit_tasklists_per_issue,
        :hard_limit_tasks_per_tasklist,
        :hard_limit_tasklists_per_issue
      ]
      validation_msg.present? && !validations_viewer_can_update.include?(validation_msg)
    end
  end
end
