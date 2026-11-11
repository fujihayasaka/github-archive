# typed: true
# frozen_string_literal: true

class Issue::Adapter::ProjectCardAdapter < Issue::Adapter::Base
  attr_reader :resource_path

  def initialize(context, project:, project_card:)
    super(context)

    @resource_path = resource_path_for(project_card.url)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
