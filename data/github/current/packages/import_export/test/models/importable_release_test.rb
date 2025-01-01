# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableReleaseTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @mannequin = create(:mannequin)
    @repository = create(:repository, owner: @user, from_example: :tags_galore)
    @release = create(:importable_release, repository: @repository)
  end

  test "has Release type" do
    assert_equal "Release", @release.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @release.importing?
    end

    test "#importing? returns false outside of import context" do
      not_importing = Release.find(@release.id)
      refute not_importing.importing?
    end
  end

  context "skips validations" do
    context "#author_access" do
      test "is skipped within an import context" do
        ImportableRelease.any_instance.expects(:author_access).never
        create(:importable_release, repository: @repository, author: @mannequin)
      end

      test "is not skipped outside an import context" do
        Release.any_instance.expects(:author_access).once
        create(:release, repository: @repository)
      end
    end
  end

  test "can be created with invalid branch and state of published" do
    @release.state = :published
    @release.target_commitish = "invalid-branch"

    assert @release.valid?
    assert @release.save
  end

  test "can be created with invalid branch and state of draft" do
    @release.state = :draft
    @release.target_commitish = "invalid-branch"

    assert @release.valid?
    assert @release.save
  end
end
