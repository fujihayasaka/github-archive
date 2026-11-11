# typed: true
# frozen_string_literal: true

# Provides a class method for setting a static global navigation context region title for each controller action.

# Example usage:
#   global_navigation_title "Projects" # sets the title for all actions in the controller
#   global_navigation_title "Issues", only: [:dashboard] # sets the title only for the dashboard action
#   global_navigation_title "Dashboard", only: [:index], path: :home_url # resolves path at request time
#   global_navigation_title "New repository", only: [:new], only_if: :no_organization_id? # conditional on predicate

module ApplicationController::GlobalNavigationContextRegionDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  DEFAULT_TITLE_ACTION_KEY = T.let(:_global_nav_default_title, Symbol)
  private_constant :DEFAULT_TITLE_ACTION_KEY

  included do
    T.bind(self, Class)
    class_attribute :_global_navigation_titles, instance_accessor: false, default: {}.freeze

    T.bind(self, T.class_of(ApplicationController))
    before_action :set_context_region_title
  end

  class_methods do
    def global_navigation_title(title, only: [], path: nil, only_if: nil)
      entry = { label: title, path: path, only_if: only_if }.compact
      keys = only.empty? ? [DEFAULT_TITLE_ACTION_KEY] : only.map(&:to_sym)
      new_entries = keys.each_with_object({}) { |key, h| h[key] = entry }
      T.unsafe(self)._global_navigation_titles = T.unsafe(self)._global_navigation_titles.merge(new_entries).freeze
    end
  end

  private

  # Called as a before_action to apply the declaratively configured title.
  sig { void }
  def set_context_region_title
    return unless header_redesign_enabled?
    return if @nav_breadcrumb.present? # Don't override if a breadcrumb has already been set

    titles = T.unsafe(self.class)._global_navigation_titles
    entry = titles[action_name.to_sym] || titles[DEFAULT_TITLE_ACTION_KEY]

    return unless entry

    # Evaluate the `only_if:` predicate when present; skip this entry if it returns falsy.
    if (condition = entry[:only_if])
      return unless method(condition).call
    end

    options = { label: entry[:label] }

    # Resolve the path at request time, supporting both static strings and dynamic symbols of path helpers
    if (path = entry[:path])
      options[:path] = path.is_a?(Symbol) ? send(path) : path # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    end

    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil, options)
  end
end
