# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::ActionSelectionListComponent < ApplicationComponent
  attr_reader :resource, :view

  def initialize(resource, view)
    @resource = resource
    @view = view
  end

  def actions
    Permissions::FineGrainedResources::Metadata.actions.keys
  end

  def action_menu_form_name
    "integration[default_permissions][#{@resource}]"
  end

  def builder
    ActionView::Helpers::FormBuilder.new(nil, nil, self, {})
  end

  def show_mandatory_label?
    @view.mandatory_permission_selected?(@resource)
  end

  def items
    actions.each_with_object([]) do |action, array|
      list_item = ProgrammaticAccess::ActionSelectionListItemMenuComponent.new(action, @resource, @view)

      array << list_item if list_item.render?
    end
  end

  memoize def enable_tooltip?
    @view.resource_parent(@resource) == "repository" && @resource == "metadata"
  end
end
