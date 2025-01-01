# typed: true
# frozen_string_literal: true

module Milestones
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::Memoizer
    include TextHelper
    include UrlHelper

    attr_reader :milestone, :issues, :showing_closed

    DESCRIPTION_PREVIEW_LENGTH = 360

    def channel
      GitHub::WebSocket::Channels.milestone_prioritized(milestone)
    end

    def current_repository
      milestone.repository
    end

    def page_title
      "#{@milestone.title} Milestone"
    end

    def formatted_description(length:)
      HTMLTruncator.new(milestone_markdown_description, length, strip_block_elements: false)
    end

    def description_preview_html
      @description_preview_html ||= begin
        formatted_description(length: DESCRIPTION_PREVIEW_LENGTH).to_html(wrap: false)
      end
    end

    def full_description_html
      @full_description_html ||= github_flavored_markdown(milestone.description)
    end

    def show_description_preview?
      full_description_html.length > DESCRIPTION_PREVIEW_LENGTH
    end

    def toggle_path
      "/#{milestone.repository.name_with_display_owner}/milestones/#{milestone.number}/toggle"
    end

    # Generate a UID
    # Used when prioritizing milestones and to check if live updates
    # for prioritization should be done for a user
    def client_uid
      SecureRandom.hex(16)
    end

    def show_blank_slate?
      no_issues_to_show?
    end

    def no_issues_to_show?
      (showing_open? && milestone.open_issue_count == 0) ||
        (showing_closed? && milestone.closed_issue_count == 0)
    end

    def show_closed_blank_slate?
      milestone.closed? && no_issues_to_show?
    end

    def show_all_done?
      milestone.open? &&
        showing_open? && # We still want people to be able to see closed issues
        milestone.open_issue_count == 0 &&
        milestone.closed_issue_count > 0
    end

    def showing_open?
      !showing_closed?
    end

    def showing_closed?
      showing_closed
    end

    def timestamp
      milestone.updated_at.to_i
    end

    def milestone_path(*args)
      urls.milestone_path(milestone.repository.owner, milestone.repository.name, milestone, *args)
    end

    def milestones_path(*args)
      urls.milestones_path(milestone.repository.owner, milestone.repository.name, *args)
    end

    def drag_disabled_message
      return if draggable?

      @drag_disabled_message ||= if !user_can_edit?
        "You do not have permission to edit this milestone."
      elsif !milestone.prioritizable?
        "Re-ordering is disabled for milestones with more than #{GitHub::Prioritizable::MAXIMUM_PRIORITIZABLE_ITEM_COUNT} issues."
      elsif showing_closed?
        "You can only reorder open issues."
      end
    end

    def user_can_edit?
      current_user && milestone.repository.pushable_by?(current_user)
    end

    def draggable?
      user_can_edit? &&
        showing_open? &&
        issues.size > 1 &&
        milestone.prioritizable?
    end

    def last_page?
      total_pages = issues.try(:total_pages)
      current_page = issues.try(:current_page)

      return true unless total_pages && current_page
      total_pages == current_page
    end

    memoize def milestone_markdown_description
      github_flavored_markdown(milestone.description)
    end
  end
end
