# typed: true
# frozen_string_literal: true

module Memex
  class IndexNavigationComponent < ApplicationComponent
    attr_reader :selected_item_id, :display_mode, :views, :display_beta_label, :owner_type

    #  selected_item_id - Can be `:classic`, `:new`, `:templates`, or `:created_by_me`
    #  beta_path - Path to the default beta page
    #  template_path - Path to the template page. If `nil` that item will be hidden
    #  classic_path - Path to the classic page
    #  display_mode - Can be `:dropdown` or `:list`
    #  owner_type - Can be `:org`, `:team` or `:repo`
    #  created_by_me_path - Path to the created by me page. If `nil`, that item will be hidden
    def initialize(selected_item_id:, beta_path:, template_path: nil, classic_path:, display_mode:, created_by_me_path: nil, recent_path: nil, owner_type: :org)
      @selected_item_id = selected_item_id
      @display_mode = display_mode
      @owner_type = owner_type

      @views = {
        recent: [recent_path, Memex::UIIndexSearch.recent_title, :recent, :clock],
        created_by_me: [created_by_me_path, Memex::UIIndexSearch.created_by_me_title, :new, :person],
        new: [beta_path, Memex::UIIndexSearch.projects_title, :new, :table],
        templates: [template_path, Memex::UIIndexSearch.templates_title, :template, :"project-template"],
        classic: classic_path ? [classic_path, Memex::UIIndexSearch.classic_projects_title, :classic, :project] : []
      }
    end

    def render?
      paths = @views.values.map { |view| view[0] }.compact
      paths.length > 1
    end

    def context_organization
      current_repository&.organization || current_organization
    end
  end
end
