# typed: true
# frozen_string_literal: true

module Memex
  class IndexHeadingComponent < ApplicationComponent
    extend T::Sig

    sig do
      params(
        search_category: Memex::UIIndexSearch::Categories,
        display_visual_heading: T::Boolean,
        include_context: T::Boolean,
        project_owner: T.nilable(T.any(User, Organization)),
        repo: T.nilable(Repository),
        team: T.nilable(Team)
      ).void
    end
    def initialize(
      search_category: Memex::UIIndexSearch::Categories::Projects,
      display_visual_heading: false,
      include_context: true,
      project_owner: nil,
      repo: nil,
      team: nil
    )
      @project_owner = project_owner
      @search_category = search_category
      @display_visual_heading = display_visual_heading
      @include_context = include_context
      @repo = repo
      @team = team
    end

    sig { returns(T.nilable(T.any(Organization, User))) }
    attr_reader :project_owner

    sig { returns(Memex::UIIndexSearch::Categories) }
    attr_reader :search_category

    sig { returns(T.nilable(Repository)) }
    attr_reader :repo

    sig { returns(T.nilable(Team)) }
    attr_reader :team

    sig { returns(T::Boolean) }
    attr_reader :display_visual_heading

    sig { returns(T::Boolean) }
    attr_reader :include_context

    def call
      render(Primer::Beta::Heading.new(tag: :h1, font_size: 3, classes: display_visual_heading ? "" : "sr-only")) { heading }
    end

    private

    sig { returns(String) }
    memoize def heading
      heading = []

      if include_context
        if team.present?
          heading.push(team&.name)
        elsif repo.present?
          heading.push(repo&.name_with_display_owner)
        elsif project_owner.present?
          heading.push(project_owner&.display_login)
        end
        heading.push(Memex::UIIndexSearch.get_search_category_title(category: search_category, always_include_project_string: true).downcase)
      else
        heading.push(Memex::UIIndexSearch.get_search_category_title(category: search_category))
      end

      heading.join(" ")
    end
  end
end
