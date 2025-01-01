# typed: true
# frozen_string_literal: true

class Issue::Adapter::LabelAdapter < Issue::Adapter::Base
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
    @resource_path = @context.repository.permalink(include_host: false) + "/labels/" + ERB::Util.url_encode(@label.name.to_s)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
