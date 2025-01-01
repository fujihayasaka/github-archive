# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAuthVersionDependencyTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  context "#auth_version" do
    test "a repository with no associated repository_auth_version defaults to 1" do
      assert_nil @repo.repository_auth_version
      assert_equal 1, @repo.auth_version
    end

    test "a repository with an associated repository_auth_version returns the version" do
      @repo.create_repository_auth_version!(version: 42)
      assert_equal 42, @repo.auth_version
    end
  end

  context "#increment_auth_version" do
    test "creates an associated repository_auth_version record if none exists" do
      assert_nil @repo.repository_auth_version

      assert_changes -> { RepositoryAuthVersion.count }, from: 0, to: 1 do
        assert_equal 2, @repo.increment_auth_version
      end

      refute_nil @repo.repository_auth_version
    end

    test "increments the version if an associated repository_auth_version record exists" do
      repository_auth_version = @repo.create_repository_auth_version!(version: 41)

      assert_no_changes -> { RepositoryAuthVersion.count } do
        assert_equal 42, @repo.increment_auth_version
      end

      assert_equal 42, repository_auth_version.reload.version
    end
  end
end
