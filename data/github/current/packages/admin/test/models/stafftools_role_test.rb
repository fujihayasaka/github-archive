# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsRoleTest < GitHub::TestCase

  test "validates presence of name" do
    role = StafftoolsRole.new
    refute role.valid?
    assert_includes role.errors[:name], "can't be blank"
  end

  test "validates uniqueness of name" do
    role = StafftoolsRole.new(name: "name").save
    role2 = StafftoolsRole.new(name: "name")
    refute role2.valid?
    assert_includes role2.errors[:name], "has already been taken"
  end

  test "rejects name containing emoji" do
    role = StafftoolsRole.new(name: "🐹")
    refute role.valid?
    assert_includes role.errors[:name], "doesn't accept 4-byte Unicode"
  end
end
