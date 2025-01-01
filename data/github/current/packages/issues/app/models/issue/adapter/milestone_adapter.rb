# typed: true
# frozen_string_literal: true

class Issue::Adapter::MilestoneAdapter < Issue::Adapter::Base
  attr_reader :resource_path

  def initialize(context, milestone:)
    super(context)
    @resource_path = @context.repository.permalink(include_host: false) + "/milestone/" + ERB::Util.url_encode(milestone.number.to_s)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
