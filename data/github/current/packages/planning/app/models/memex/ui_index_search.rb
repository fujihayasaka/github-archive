# typed: strict
# frozen_string_literal: true

module Memex
  class UIIndexSearch
    extend T::Sig

    # Represents valid search categories for memex index pages
    class Categories < T::Enum
      enums do
        # Recent projects
        Recent = new(:recent)
        # Projects created by user
        CreatedByMe = new(:created_by_me)
        # Project templates
        Templates = new(:templates)
        # Legacy projects
        Classic = new(:classic)
        # Projects
        Projects = new(:new)
      end
    end

    sig do
      params(
        category: Memex::UIIndexSearch::Categories,
        # For subcategories (recent, created by me, templates), whether or not to include "Projects" in the title
        always_include_project_string: T::Boolean
      ).returns(String)
    end
    def self.get_search_category_title(category:, always_include_project_string: false)
      str = case category
      when Memex::UIIndexSearch::Categories::Recent
        always_include_project_string ? "Recently viewed projects" : "Recently viewed"
      when Memex::UIIndexSearch::Categories::CreatedByMe
        always_include_project_string ? "Projects created by me" : "Created by me"
      when Memex::UIIndexSearch::Categories::Templates
        always_include_project_string ? "Project templates" : "Templates"
      when Memex::UIIndexSearch::Categories::Classic
        "Projects (classic)"
      else
        "Projects"
      end
    end

    sig { params(always_include_project_string: T::Boolean).returns(String) }
    def self.recent_title(always_include_project_string: false)
      self.get_search_category_title(category: Memex::UIIndexSearch::Categories::Recent, always_include_project_string: false)
    end

    sig { params(always_include_project_string: T::Boolean).returns(String) }
    def self.created_by_me_title(always_include_project_string: false)
      self.get_search_category_title(category: Memex::UIIndexSearch::Categories::CreatedByMe, always_include_project_string:)
    end

    sig { params(always_include_project_string: T::Boolean).returns(String) }
    def self.templates_title(always_include_project_string: false)
      self.get_search_category_title(category: Memex::UIIndexSearch::Categories::Templates, always_include_project_string:)
    end

    sig { params(always_include_project_string: T::Boolean).returns(String) }
    def self.classic_projects_title(always_include_project_string: false)
      self.get_search_category_title(category: Memex::UIIndexSearch::Categories::Classic, always_include_project_string:)
    end

    sig { returns(String) }
    def self.projects_title
      self.get_search_category_title(category: Memex::UIIndexSearch::Categories::Projects)
    end
  end
end
