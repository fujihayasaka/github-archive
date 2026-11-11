# typed: true
# frozen_string_literal: true

class Issue::Adapter::LabelAdapter < Issue::Adapter::Base
  include GitHub::RouteHelpers

  attr_reader :id
  attr_reader :name
  attr_reader :name_html
  attr_reader :description
  attr_reader :color
  attr_reader :resource_path

  def initialize(context, label:)
    super(context)

    @id = label.global_relay_id
    @label = label
    @name = label.name
    @name_html = label.name_html
    @description = label.description
    @color = label.color
    @resource_path = gh_label_path(label, context.repository)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
