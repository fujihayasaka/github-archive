# typed: true
# frozen_string_literal: true

class Discussions::EmptyStateComponent < ApplicationComponent
  include GitHub::Memoizer

  # repository - a Repository
  # discussions - an Array or ActiveRecord::Relation of Discussion records in the repository
  # parsed_discussions_query - an Array result from Search::Queries::DiscussionQuery#parse
  # can_create_discussion - Boolean indicating whether the currently authenticated user can create a new discussion in the repository
  # new_discussion_hydro_attrs - Hash of Hydro attributes to use on the 'new discussion' link
  # selected_category_slug - String slug of a DiscussionCategory that is currently selected on the page
  def initialize(repository:, discussions:, parsed_discussions_query:, can_create_discussion:, new_discussion_hydro_attrs:, selected_category_slug:)
    @repository = repository
    @discussions = discussions
    @parsed_discussions_query = parsed_discussions_query
    @can_create_discussion = can_create_discussion
    @new_discussion_hydro_attrs = new_discussion_hydro_attrs
    @selected_category_slug = selected_category_slug
  end

  private

  attr_reader :new_discussion_hydro_attrs

  def can_create_discussion?
    @can_create_discussion
  end

  memoize def render_empty_state?
    return false unless @repository.discussions.empty?
    return true if @parsed_discussions_query == Discussion::ListControlFlow::DEFAULT_SEARCH_QUERY
    @parsed_discussions_query.empty?
  end

  memoize def title
    if render_empty_state?
      "Welcome to discussions!"
    elsif @parsed_discussions_query.include?([:is, "answered"])
      other_terms = @parsed_discussions_query.any? { |term| term != [:is, "answered"] }
      "There are no#{" matching" if other_terms} answered discussions."
    elsif @parsed_discussions_query.include?([:is, "unanswered"])
      other_terms = @parsed_discussions_query.any? { |term| term != [:is, "unanswered"] }
      "There are no#{" matching" if other_terms} unanswered discussions."
    else
      "There are no matching discussions."
    end
  end

  memoize def generated_new_discussion_path
    new_discussion_path(@repository.owner_display_login, @repository, category: @selected_category_slug)
  end

  def render?
    @discussions.empty?
  end
end
