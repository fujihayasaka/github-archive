# typed: true
# frozen_string_literal: true

module DiscussionsControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers

  include GlobalNavigationHelper

  DEFAULT_PER_PAGE = 25

  abstract!

  requires_ancestor { ApplicationController }

  private

  sig { abstract.returns(T::Array[T.untyped]) }
  def parsed_discussions_query; end

  sig { abstract.returns(T.nilable(Repository)) }
  def current_repository; end

  sig { abstract.returns(T.nilable(Organization)) }
  def this_organization; end

  sig { abstract.returns(T::Boolean) }
  def is_org_level?; end

  sig { returns Integer }
  def per_page
    DEFAULT_PER_PAGE
  end

  sig { params(category_slug: T.nilable(String)).returns(T.nilable(T::Boolean)) }
  def include_answer_filters?(category_slug)
    search_term_values = Discussion::SearchTerm.values(:is, parsed_discussions_query: parsed_discussions_query)
    # If the filter is already applied, always display the options
    if search_term_values.any? { |value| Discussions::FilterComponent::ANSWERS_ENABLED_OPTIONS.include?(value) }
      return true
    end
    return current_repository&.discussion_categories&.any?(&:supports_mark_as_answer?) unless category_slug
    category = DiscussionCategory.find_by(repository: current_repository, slug: category_slug)
    category.present? && category.supports_mark_as_answer?
  end

  sig { void }
  def set_org_context_crumb
    return unless header_redesign_enabled?
    return if this_organization.nil?
    set_nav_breadcrumb ContextRegion::Factory.build(this_organization, current_user: current_user)
  end

  sig { void }
  def handle_choose_category_redirect
    if missing_or_invalid_category?
      flash[:notice] = "Sorry, we didn't recognize that category! Please choose one of the following valid categories."
      redirect_to agnostic_choose_category_discussion_path(current_repository,
        org: is_org_level? ? this_organization : nil)
    end
  end

  sig { returns T::Boolean }
  def missing_or_invalid_category?
    params[:category].blank? || available_categories.where(slug: params[:category]).none?
  end

  sig { returns ActiveRecord::Relation }
  def available_categories
    current_repository&.available_discussion_categories_for_actor(current_user) || DiscussionCategory.none
  end
end
