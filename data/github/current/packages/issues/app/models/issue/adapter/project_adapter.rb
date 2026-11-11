# typed: true
# frozen_string_literal: true

class Issue::Adapter::ProjectAdapter < Issue::Adapter::Base
  attr_reader :id
  attr_reader :name
  attr_reader :resource_path

  def initialize(context, project:)
    super(context)

    @id = project.global_relay_id
    @name = project.name
    @resource_path = resource_path_for(project.url)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
