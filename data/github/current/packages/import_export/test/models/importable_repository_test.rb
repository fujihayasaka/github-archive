# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableRepositoryTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @repo = create(:importable_repository, owner: @org)
  end

  test "has Repository type" do
    assert_equal "Repository", @repo.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @repo.importing?
    end

    test "#importing? returns false outside of import context" do
      non_import_repo = Repositories::Public.find_active!(@repo.id)
      refute non_import_repo.importing?
    end
  end

  context "skipped validations" do
    test "#can_add_user? returns true when the addee has been suspended within the context of an import" do
      addee = create(:user)
      addee.suspend("reasons")

      assert @repo.can_add_user?(addee, @org)
    end

    test "#can_add_user? returns false when the addee has been suspended outside the context of an import" do
      addee = create(:user)
      addee.suspend("reasons")

      repo = Repositories::Public.find_active!(@repo.id)
      refute repo.can_add_user?(addee, @org)
      assert_includes repo.errors[:base], "User is suspended"
    end
  end

  test "has repository_sequence type" do
    assert @repo.repository_sequence.present?
  end
end
