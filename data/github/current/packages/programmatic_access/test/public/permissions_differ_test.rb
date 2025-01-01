# typed: true
# frozen_string_literal: true

require "test_helper"

class PermissionsDifferTest < GitHub::TestCase

  def described_class
    ::PermissionsDiffer
  end

  test "#added_permissions" do
    added_permissions = described_class.new(
      previous_permissions: {},
      new_permissions: { "contents" => :read },
    ).added_permissions

    assert_equal({ "contents" => :read }, added_permissions)

    added_permissions = described_class.new(
      previous_permissions: { "issues" => :write },
      new_permissions: { "contents" => :read },
    ).added_permissions

    assert_equal({ "contents" => :read }, added_permissions)

    added_permissions = described_class.new(
      previous_permissions: { "issues" => :write },
      new_permissions: { "issues" => :write },
    ).added_permissions

    assert_predicate added_permissions, :empty?
  end

  test "#downgraded_permissions" do
    downgraded_permissions = described_class.new(
      previous_permissions: { "contents" => :write },
      new_permissions: { "contents" => :read },
    ).downgraded_permissions

    assert_equal({ "contents" => :read }, downgraded_permissions)

    downgraded_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => :read },
    ).downgraded_permissions

    assert_predicate downgraded_permissions, :empty?
  end

  test "#downgraded_permissions recognizes actions as strings" do
    downgraded_permissions = described_class.new(
      previous_permissions: { "contents" => :write },
      new_permissions: { "contents" => "read" },
    ).downgraded_permissions

    assert_equal({ "contents" => :read }, downgraded_permissions)

    downgraded_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => "read" },
    ).downgraded_permissions

    assert_predicate downgraded_permissions, :empty?
  end

  test "#downgraded_permissions recognizes admin action" do
    downgraded_permissions = described_class.new(
      previous_permissions: { "members" => :admin },
      new_permissions: { "members" => :write },
    ).downgraded_permissions

    assert_equal({ "members" => :write }, downgraded_permissions)

    downgraded_permissions = described_class.new(
      previous_permissions: { "members" => :admin },
      new_permissions: { "members" => :read },
    ).downgraded_permissions

    assert_equal({ "members" => :read }, downgraded_permissions)
  end

  test "#removed_permissions" do
    removed_permissions = described_class.new(
      previous_permissions: { "contents" => :write },
      new_permissions: {},
    ).removed_permissions

    assert_equal({ "contents" => :write }, removed_permissions)

    removed_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => :read },
    ).removed_permissions

    assert_predicate removed_permissions, :empty?
  end

  test "#unchanged_permissions" do
    unchanged_permissions = described_class.new(
      previous_permissions: { "contents" => :write },
      new_permissions: { "contents" => :write },
    ).unchanged_permissions

    assert_equal({ "contents" => :write }, unchanged_permissions)

    unchanged_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => :write },
    ).unchanged_permissions

    assert_predicate unchanged_permissions, :empty?
  end

  test "#unchanged_permissions recognizes actions as strings" do
    unchanged_permissions = described_class.new(
      previous_permissions: { "contents" => :write },
      new_permissions: { "contents" => "write" },
    ).unchanged_permissions

    assert_equal({ "contents" => :write }, unchanged_permissions)

    unchanged_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => "write" },
    ).unchanged_permissions

    assert_predicate unchanged_permissions, :empty?
  end

  test "#upgraded_permissions" do
    upgraded_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => :write },
    ).upgraded_permissions

    assert_equal({ "contents" => :write }, upgraded_permissions)

    upgraded_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => :read },
    ).upgraded_permissions

    assert_predicate upgraded_permissions, :empty?
  end

  test "#upgraded_permissions recognizes actions as strings" do
    upgraded_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => "write" },
    ).upgraded_permissions

    assert_equal({ "contents" => :write }, upgraded_permissions)

    upgraded_permissions = described_class.new(
      previous_permissions: { "contents" => :read },
      new_permissions: { "contents" => "read" },
    ).upgraded_permissions

    assert_predicate upgraded_permissions, :empty?
  end

  test "#upgraded_permissions recognizes admin action" do
    upgraded_permissions = described_class.new(
      previous_permissions: { "members" => :read },
      new_permissions: { "members" => :admin },
    ).upgraded_permissions

    assert_equal({ "members" => :admin }, upgraded_permissions)

    upgraded_permissions = described_class.new(
      previous_permissions: { "members" => :write },
      new_permissions: { "members" => :admin },
    ).upgraded_permissions

    assert_equal({ "members" => :admin }, upgraded_permissions)
  end
end
