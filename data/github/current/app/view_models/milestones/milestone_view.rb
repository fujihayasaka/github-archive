# typed: true
# frozen_string_literal: true

module Milestones
  class MilestoneView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::TagHelper
    include GitHub::Memoizer
    include TextHelper
    include UrlHelper

    attr_reader :repository, :milestone

    alias_attribute :current_repository, :repository

    # repo      - the repository associated with the Milestone
    # milestone - the current Milestone
    def initialize(repo, milestone)
      @repository = repo
      @milestone = milestone
    end

    def not_due?
      milestone.due_on.nil? && milestone.open?
    end

    def past_due?
      milestone.past_due? && milestone.open?
    end

    def milestone_due_class
      (" notdue" if not_due?) || (" pastdue" if past_due?)
    end

    def formatted_description(length:, strip_block_elements: true)
      HTMLTruncator.new(milestone_markdown_description, length, strip_block_elements: strip_block_elements)
    end

    def description_preview_html
      @description_preview_html ||= begin
        fragment = formatted_description(length: 70, strip_block_elements: true).to_html(wrap: false)
        more_tag = content_tag(:button, "(more)", type: "button", "aria-expanded": false, class: "btn-link expand-more js-details-target") # rubocop:disable Rails/ViewModelHTML
        content_tag(:p, fragment + more_tag) # rubocop:disable Rails/ViewModelHTML
      end
    end

    def full_description_html
      @full_description_html ||= formatted_description(length: Milestone::MAX_DESCRIPTION_LENGTH, strip_block_elements: false).to_html
    end

    def show_description_preview?
      full_description_html.length > description_preview_html.length
    end

    def has_description?
      milestone.description.present?
    end

    def toggle_path
      "/#{repository.name_with_display_owner}/milestones/#{milestone.number}/toggle"
    end

    # For use in searching issues/PRs with milestone:"The Milestone Name".
    def milestone_title_search_string
      "milestone:#{Search::ParsedQuery.encode_value(milestone.title)}"
    end

    def milestone_open_query
      "is:open #{milestone_title_search_string}"
    end

    def milestone_closed_query
      "is:closed #{milestone_title_search_string}"
    end

    def edit_path
      urls.edit_milestone_path(repository.owner, repository, milestone)
    end

    def delete_path
      urls.milestone_path(repository.owner, repository, milestone.number)
    end

    def milestone_path
      urls.milestone_path(repository.owner, repository, milestone)
    end

    memoize def milestone_markdown_description
      github_flavored_markdown(milestone.description)
    end
  end
end
