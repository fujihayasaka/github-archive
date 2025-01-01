# typed: strict
# frozen_string_literal: true

class Discussions::FilterComponent < ApplicationComponent
  extend T::Sig

  OPTIONS = T.let(%w[
    open
    closed
    locked
    unlocked
  ], T::Array[String])

  ANSWERS_ENABLED_OPTIONS = T.let(%w[
    answered
    unanswered
  ], T::Array[String])

  sig do
    params(
      current_repository: Repository,
      include_answer_filters: T::Boolean,
      parsed_discussions_query: T::Array[T.untyped],
      org_param: T.nilable(String)
    ).void
  end
  def initialize(current_repository:, include_answer_filters:, parsed_discussions_query: [], org_param: nil)
    @current_repository = current_repository
    @include_answer_filters = include_answer_filters
    @parsed_discussions_query = parsed_discussions_query
    @org_param                = org_param
  end

  private

  sig { returns(Repository) }
  attr_reader :current_repository

  sig { returns(T::Array[T.untyped]) }
  attr_reader :parsed_discussions_query

  sig { returns(T.nilable(String)) }
  attr_reader :org_param

  sig { returns(T::Boolean) }
  def include_answer_filters?
    @include_answer_filters
  end

  sig { returns(String) }
  def button_label
    if Discussion::SearchTerm.values(:is, parsed_discussions_query: parsed_discussions_query).any?
      "Filter: #{search_terms}"
    else
      "Filter"
    end
  end

  sig { returns(String) }
  def search_terms
    Discussion::SearchTerm.values(:is, parsed_discussions_query: parsed_discussions_query).map(&:capitalize)
      .join(", ")
  end

  sig { returns(T::Array[String]) }
  memoize def options
    selectable_options = OPTIONS

    if include_answer_filters?
      selectable_options = selectable_options + ANSWERS_ENABLED_OPTIONS
    end

    selectable_options
  end

  sig { returns(T::Array[String]) }
  memoize def selected_options
    values = Discussion::SearchTerm.values(:is, parsed_discussions_query: parsed_discussions_query)
    return [] unless values.present?
    options.intersection(values)
  end

  sig { params(option: String).returns(T::Boolean) }
  def selected?(option)
    selected_options.include?(option)
  end
end
