# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::ActionSelectionListComponent < ApplicationComponent
  def initialize(resource, view)
    @resource = resource
    @view = view
  end

  def actions
    Permissions::FineGrainedResources::Metadata.actions.keys
  end
end
