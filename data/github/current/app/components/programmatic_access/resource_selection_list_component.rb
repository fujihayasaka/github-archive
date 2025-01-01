# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::ResourceSelectionListComponent < ApplicationComponent

  renders_one :description, -> (**system_arguments) do
    system_arguments[:tag] = :p
    opts = {
      font_size: :small,
      color: :muted,
      m: 0,
    }.merge(system_arguments)
    Primer::BaseComponent.new(**T.unsafe(opts))
  end

  attr_reader :data_attribute, :hidden

  VALID_RESOURCE_PARENTS = [
    Repository, Organization, User, Business
  ]

  def initialize(resource_parent:, view:, hidden: false, data_attribute: nil)
    @resource_parent = resource_parent
    @view            = view # Instance of Integrations::PermissionsView
    @hidden          = hidden

    # attribute must appear in erb file to pass linter
    @data_attribute  = data_attribute
  end

  def permission_type
    @resource_parent.name.downcase
  end

  def granted?(resource)
    @view.granted_permissions.key?(resource)
  end

  def render?
    VALID_RESOURCE_PARENTS.include?(@resource_parent)
  end

  def heading
    permissions = case @resource_parent.name
    when "User"; "Account"
    when "Business"; "Enterprise"
    else; @resource_parent.name
    end

    t("personal_access_tokens.permission_selection.heading", permission_type: permissions)
  end

  memoize def resources
    @resources = case @resource_parent.name
    when "Repository"
      Repository::Resources.subject_types_for(@view.programmatic_actor)
    when "Organization"
      Organization::Resources.subject_types_for(@view.programmatic_actor)
    when "User"
      User::Resources.subject_types_for(@view.programmatic_actor)
    when "Business"
      Business::Resources.subject_types_for(@view.programmatic_actor)
    end

    ProgrammaticAccess::ResourceListHelpers.sort_by_displayed_titles(@resources)
  end
end
