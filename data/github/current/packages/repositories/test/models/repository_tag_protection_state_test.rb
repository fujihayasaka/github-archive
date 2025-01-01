# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTagProtectionStateTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  context ".for_tag" do
    test "defaults to * as pattern" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id)
      assert_equal tag_protection.pattern, "*"
    end

    test "returns a `*` pattern if there is one" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "*")
      record = RepositoryTagProtectionState.for_tag(@repo, "anything")
      assert_equal tag_protection, record
    end

    test "returns a matching pattern if there is one" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "a-tag")
      record = RepositoryTagProtectionState.for_tag(@repo, "a-tag")
      assert_equal tag_protection, record
    end

    test "returns nil if there are no records for this repo" do
      refute RepositoryTagProtectionState.for_tag(@repo, "a-tag")
    end

    test "returns nil if there are no matching patterns" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "pizza")
      refute RepositoryTagProtectionState.for_tag(@repo, "a-tag")
    end
  end

  context ".for_repository" do
    test "returns all records for the given repository" do
      # .for_repository calls scopes that set ordering (wildcard first, then by pattern length)
      two = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "12")
      one = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "1")
      three = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "123")
      wildcard = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "*")

      records = RepositoryTagProtectionState.for_repository(@repo)
      assert_equal [wildcard, one, two, three], records
    end
  end

  context ".tag_is_protected?" do
    test "returns true if the pattern is a wildcard string" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "*")
      assert RepositoryTagProtectionState.tag_is_protected?([tag_protection], "anything")
    end

    test "returns true if the tag matches the pattern" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "v1.*")
      assert RepositoryTagProtectionState.tag_is_protected?([tag_protection], "v1.0.0")
    end

    test "returns false if the tag does not match the pattern" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "v1.*")
      refute RepositoryTagProtectionState.tag_is_protected?([tag_protection], "pizza")
    end
  end

  context "#wildcard?" do
    test "returns true if the pattern is a wildcard string" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "*")
      assert tag_protection.wildcard?
    end

    test "returns false if the pattern is not a wildcard string" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "v1.*")
      refute tag_protection.wildcard?
    end
  end

  context "#matches?" do
    test "returns true if the tag matches the pattern" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "v1.*")
      assert tag_protection.matches?("v1.1.1")
    end

    test "returns false if the tag does not match the pattern" do
      tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "v1.*")
      refute tag_protection.matches?("pizza")
    end
  end

  context "scopes" do
    context ".wildcard_first" do
      test "returns record with `pattern: *` first" do
        wildcard_tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "*")
        tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "v1.*")
        records = RepositoryTagProtectionState.wildcard_first.where(repository_id: @repo.id)
        assert_equal wildcard_tag_protection, records.first
        assert_equal tag_protection, records.last
      end

      test "returns other records if there are no wildcards" do
        tag_protection = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "v1.*")
        records = RepositoryTagProtectionState.wildcard_first.where(repository_id: @repo.id)
        assert_equal tag_protection, records.first
      end
    end

    context ".by_pattern_length" do
      test "returns records in order of pattern length" do
        two = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "12")
        one = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "1")
        three = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "123")
        records = RepositoryTagProtectionState.by_pattern_length.where(repository_id: @repo.id)
        assert_equal one, records[0]
        assert_equal two, records[1]
        assert_equal three, records[2]
      end
    end
  end

  context "validation" do
    test "pattern is required" do
      with_errors = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: nil)
      assert with_errors.errors.any?
      assert_equal "is invalid", with_errors.errors[:pattern].first
    end

    test "pattern must match a valid regex" do
      no_errors = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "a-tag")
      refute no_errors.errors.any?

      with_errors = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "this is invalid")
      assert with_errors.errors.any?
      assert_equal "is invalid", with_errors.errors[:pattern].first
    end

    test "patterns are unique per repo" do
      no_errors = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "test")
      refute no_errors.errors.any?
      duplicate_pattern = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "test")
      assert duplicate_pattern.errors.any?
      new_repo_pattern = RepositoryTagProtectionState.create(repository_id: create(:repository).id, pattern: "test")
      refute new_repo_pattern.errors.any?
    end

    test "repository's plan must support the feature", skip_enterprise: true do
      @repo.update!(private: true)
      with_errors = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "test")
      assert_equal ["plan does not support tag protection"], with_errors.errors[:repository]

      @repo.owner.plan = GitHub::Plan.pro
      @repo.owner.save!
      no_errors = RepositoryTagProtectionState.create(repository_id: @repo.id, pattern: "test")
      refute no_errors.errors.any?
    end
  end
end
