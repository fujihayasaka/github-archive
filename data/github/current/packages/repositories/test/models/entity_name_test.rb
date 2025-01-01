# typed: strict
# frozen_string_literal: true

require "test_helper"

class EntityNameTest < GitHub::TestCase
  test "good names are good" do
    assert EntityName.new("my-name").valid?
  end

  test "cannot end in .wiki" do
    name = EntityName.new("name.wiki")
    refute name.valid?
  end

  test "strips off .git" do
    name = EntityName.new("name.git")
    assert name.valid?
    assert_equal "name", name.value
  end

  test "strips off .git multiple times" do
    name = EntityName.new("name.git.git")
    assert name.valid?
    assert_equal "name", name.value
  end

  test "strips off .git case insensitively" do
    name = EntityName.new("name.gIT")
    assert name.valid?
    assert_equal "name", name.value
  end

  test "normalizes the name" do
    { "Merb Core" => "Merb-Core",
      "linux 2.6" => "linux-2.6",
      "∑rror" => "-rror",
      "some--thing" => "some--thing",
      "-extra--dashes-" => "-extra--dashes-",
    }.each do |name, normalized|
      name = EntityName.new(name)
      assert_equal normalized, name.value
    end
  end
end
