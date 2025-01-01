# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::ActionSelectionListItemBaseComponent < ApplicationComponent
  def initialize(action, resource, view)
    @action = action
    @resource = resource
    @view = view
  end

  def checked?
    @view.selected_permission?(@resource, @action)
  end

  def data_attributes
    {
      "permission" => @action,
      "resource" => @resource,
      "resource-parent" => resource_parent,
    }
  end

  def disabled?
    return true if @view&.disabled_for_all_actions?

    case @action
    when :none
      @view.mandatory_permission_selected?(@resource)
    when :read
      Permissions::ResourceRegistry.writeonly_subject_type?(@resource)
    when :write
      Permissions::ResourceRegistry.readonly_subject_type?(@resource)
    else
      false
    end
  end

  def id
    "integration_permission_#{@resource}_#{@action}"
  end

  def name
    "integration[default_permissions][#{@resource}]"
  end

  def label_text
    Permissions::FineGrainedResources::Metadata.action_description(@action)
  end

  def render?
    case @action
    when :none, :read, :write
      true
    when :admin
      Permissions::ResourceRegistry.adminable_subject_type?(@resource)
    else
      false
    end
  end

  def value
    case @action
    when :read, :write, :admin
      @action.to_s
    else
      ""
    end
  end

  private

  # Public: the parent of the given resource as a downcased string.
  #
  # E.g. "issues" => "repository", "members" => "organization" etc.
  #
  # Returns a String.
  def resource_parent
    "#{Permissions::ResourceRegistry.parent_of(@resource)}".downcase
  end
end
