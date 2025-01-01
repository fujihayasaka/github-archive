# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::ResourceSelectionListItemComponent < ApplicationComponent
  attr_reader :metadata

  delegate :description, :docs_url, :title, to: :metadata

  def initialize(resource, view)
    @resource = resource
    @metadata = Permissions::FineGrainedResources::Metadata.new(@resource, view.programmatic_actor)
    @view = view
  end

  def mandatory?
    @view.mandatory_permission_selected?(@resource)
  end
end
