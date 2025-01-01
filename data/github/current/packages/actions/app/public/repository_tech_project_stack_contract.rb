# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class RepositoryTechProjectStackContract
  attr_accessor :name, :size, :settings, :id

  def initialize(name, size, settings)
    @name = name
    @size = size || 0
    @settings = settings
    @id = nil
  end

  def is_language?
    size > 0
  end

  def is_cloud_resource?
    tech_stack = Scout::TechStack.find_by_name(name) ||
      Scout::TechStack.find_by_alias(name)
    !!tech_stack && tech_stack.type.to_s == "cloudresource"
  end

  def ==(other)
    other.is_a?(self.class) &&
    name == other.name
  end
  alias eql? ==

  def hash
    name.hash
  end
end
