# typed: true
# frozen_string_literal: true

module MemexProject::ViewDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { MemexProject }

  included do
    T.bind(self, T.class_of(MemexProject))
    has_many :memex_project_views, inverse_of: :memex_project
    destroy_dependents_in_background :memex_project_views
    accepts_nested_attributes_for :memex_project_views
    prioritizes :memex_project_views,
      with: :memex_project_views,
      inverse_of: :memex_project,
      multiple_associations: true

    batch_method(:memex_project_views_with_filtered_layouts) do |memex_projects, layouts|
      views = MemexProjectView.with_layouts(layouts)
        .where(memex_project_id: memex_projects.map(&:id))
        .group_by(&:memex_project_id)
      memex_projects.index_with { |memex_project| views[memex_project.id] || [] }
    end
  end

  sig { params(view: MemexProjectView, options: T.untyped).returns(T::Boolean) }
  def save_view_with_priority!(view, **options)
    if options.blank?
      last_view_scope = prioritized_memex_project_views
      last_view_scope = last_view_scope.where.not(id: view.id) if view.id
      options = { after: last_view_scope.last }.compact
    end
    view.validate!
    success = prioritize_dependent!(view, **options)
    success.present?
  end

  sig { returns(T.nilable(MemexProjectView)) }
  def default_view
    prioritized_memex_project_views.last # Return the lowest priority element
  end

  private

  sig { void }
  def create_default_view
    view = memex_project_views.build({ creator: creator })
    # The default view should be saved at the top, rather than positioned after an existing view,
    # since this is the first view there will be none before it.
    self.save_view_with_priority!(view, **{ position: :top })
  end
end
