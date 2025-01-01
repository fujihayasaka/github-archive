# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanCustomPatternTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @user = create(:user)
    @pattern = create(
      :secret_scan_custom_pattern,
      repository: @repo,
      owner: @org,
      display_name: "bar API key",
      slug: "bar_api_key",
      secret_type: "cp__#{@repo.id}_bar_api_key",
      expression: "bar_api_[0-9A-Za-z]",
      post_processing_expressions: {},
      created_by_id: @user.id,
    )
  end

  context "validation" do
    test "requires an owner" do
      pattern = SecretScanCustomPattern.new(owner_id: nil)

      refute_predicate pattern, :valid?
      refute_empty pattern.errors[:owner_id]
    end

    test "requires a display name" do
      pattern = SecretScanCustomPattern.new(repository_id: @repo.id, owner_id: @repo.owner.id, created_by_id: @user.id, display_name: nil)

      refute_predicate pattern, :valid?
      refute_empty pattern.errors[:display_name]
    end

    test "requires a slug" do
      pattern = SecretScanCustomPattern.new(repository_id: @repo.id, owner_id: @repo.owner.id, created_by_id: @user.id, display_name: "foo API key", slug: nil)

      refute_predicate pattern, :valid?
      refute_empty pattern.errors[:slug]
    end

    test "requires a secret type" do
      pattern = SecretScanCustomPattern.new(repository_id: @repo.id, owner_id: @repo.owner.id, created_by_id: @user.id, display_name: "foo API key", slug: "foo_api_key", secret_type: nil)

      refute_predicate pattern, :valid?
      refute_empty pattern.errors[:secret_type]
    end

    test "requires an expression" do
      pattern = SecretScanCustomPattern.new(repository_id: @repo.id, owner_id: @repo.owner.id, created_by_id: @user.id, display_name: "foo API key", slug: "foo_api_key", secret_type: "cp__1_foo_api_key", expression: nil)

      refute_predicate pattern, :valid?
      refute_empty pattern.errors[:expression]
    end
  end

  context ".create_repo_pattern!" do
    test "creates the pattern for the given set of attributes" do
      attributes = {
        display_name: "test API key",
        slug: "test_api_key",
        secret_type: "cp__#{@repo.id}_test_api_key",
        expression: "test_api_[0-9A-Za-z]",
        post_processing_expressions: {},
        created_by_id: @user.id
      }
      pattern = assert_difference("SecretScanCustomPattern.count", 1) do
        SecretScanCustomPattern.create_repo_pattern!(@repo, attributes)
      end

      refute_nil pattern
      assert_equal :repo, pattern.scope.to_sym
    end
  end
end
