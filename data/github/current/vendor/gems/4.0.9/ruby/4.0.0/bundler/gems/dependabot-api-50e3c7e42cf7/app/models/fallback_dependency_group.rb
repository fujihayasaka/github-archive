# frozen_string_literal: true

class FallbackDependencyGroup
  attr_reader :name

  def initialize(name:)
    raise ArgumentError if name.blank?

    @name = name
  end

  def applies_to
    DependencyGroup::APPLIES_TO_SECURITY_UPDATES
  end

  def rules
    { "patterns" => ["*"] }
  end

  def serialize
    {
      "name" => name,
      "rules" => rules,
      "applies-to" => applies_to,
    }
  end
end
