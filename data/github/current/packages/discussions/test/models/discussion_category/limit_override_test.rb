# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCategory::LimitOverrideTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository, has_discussions: true)
    @staff = create(:staff_admin_user)
  end

  setup do
    @override = DiscussionCategory::LimitOverride.new(
      repository: @repository,
      actor: @staff,
    )
  end

  context ".for" do
    test "returns currently set limit" do
      @override.set(limit: 30)
      assert_equal 30, DiscussionCategory::LimitOverride.for(@repository)
    end

    test "returns nil if no limit is set" do
      assert_nil DiscussionCategory::LimitOverride.for(@repository)
    end

    test "returns nil if repository is not present" do
      assert_nil DiscussionCategory::LimitOverride.for(nil)
    end
  end

  context "#value" do
    test "returns currently set limit" do
      @override.set(limit: 30)
      assert_equal 30, @override.value
    end

    test "returns nil if no limit is set" do
      assert_nil @override.value
    end

    test "returns nil if repository is not present" do
      override = DiscussionCategory::LimitOverride.new(
        repository: nil,
        actor: @staff,
      )
      assert_nil override.value
    end
  end

  context "#set" do
    test "allows setting an override" do
      assert_nil @override.value

      result = @override.set(limit: 30)

      assert_predicate result, :success?
      assert_equal 30, @override.value
    end

    test "limit must be over minimum" do
      limit = DiscussionCategory::LimitOverride::MINIMUM_LIMIT - 1
      assert_nil @override.value

      result = @override.set(limit: limit)

      refute_predicate result, :success?
      assert_equal [
        "Limit must be at least #{DiscussionCategory::LimitOverride::MINIMUM_LIMIT}",
      ], result.errors
      assert_nil @override.value
    end

    test "requires a repository" do
      override = DiscussionCategory::LimitOverride.new(
        repository: nil,
        actor: @staff,
      )
      assert_nil override.value

      result = override.set(limit: 30)

      refute_predicate result, :success?
      assert_equal ["Repository can't be blank"], result.errors
      assert_nil override.value
    end

    test "requires an actor" do
      override = DiscussionCategory::LimitOverride.new(
        repository: @repository,
        actor: nil,
      )
      assert_nil override.value

      result = override.set(limit: 30)

      refute_predicate result, :success?
      assert_equal [
        "Actor can't be blank",
        "Actor must be a site admin",
      ], result.errors
      assert_nil override.value
    end

    test "actor must be a site admin" do
      override = DiscussionCategory::LimitOverride.new(
        repository: @repository,
        actor: @repository.owner,
      )
      assert_nil override.value

      result = override.set(limit: 30)

      refute_predicate result, :success?
      assert_equal ["Actor must be a site admin"], result.errors
      assert_nil override.value
    end
  end

  context "#delete" do
    test "allows deleting an override" do
      @override.set(limit: 30)
      assert_equal 30, @override.value

      result = @override.delete

      assert_predicate result, :success?
      assert_nil @override.value
    end

    test "works even if override is not set" do
      assert_nil @override.value

      result = @override.delete

      assert_predicate result, :success?
      assert_nil @override.value
    end

    test "requires a repository" do
      override = DiscussionCategory::LimitOverride.new(
        repository: nil,
        actor: @staff,
      )

      result = override.delete

      refute_predicate result, :success?
      assert_equal ["Repository can't be blank"], result.errors
    end

    test "requires an actor" do
      override = DiscussionCategory::LimitOverride.new(
        repository: @repository,
        actor: nil,
      )

      result = override.delete

      refute_predicate result, :success?
      assert_equal [
        "Actor can't be blank",
        "Actor must be a site admin",
      ], result.errors
    end

    test "actor must be a site admin" do
      override = DiscussionCategory::LimitOverride.new(
        repository: @repository,
        actor: @repository.owner,
      )
      result = override.delete

      refute_predicate result, :success?
      assert_equal ["Actor must be a site admin"], result.errors
    end
  end
end
