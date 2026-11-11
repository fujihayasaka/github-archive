# frozen_string_literal: true

class NullableSerializer < ActiveRecord::Coders::YAMLColumn
  def load(yaml)
    return nil if yaml.nil?

    super
  end

  def dump(yaml)
    return nil if yaml.nil?

    super
  end
end
