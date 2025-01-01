# typed: true
# frozen_string_literal: true

require "test_helper"

class TestAttribute < Permissions::Attributes::Default
  def actor_attributes(actor)
    super.merge("actor_attr" => actor)
  end
end

class Permissions::Attributes::DefaultTest < GitHub::TestCase

  test "serialize actor attributes" do
    attrs = TestAttribute.new("participant").serialized_actor_attributes("actor")

    assert_equal "actor", attrs.find { |attr| attr.id == "actor_attr" }.value.string_value
  end
end
