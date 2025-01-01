# typed: true
# frozen_string_literal: true

require "test_helper"

class UploadDirectoryValidatorTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @manifest = UploadManifest.create(repository: @repo, uploader: @owner)
  end

  context "validating directory path name" do
    test "rejects directory navigation characters" do
      @manifest.directory = "/../../../"
      refute @manifest.valid?
      refute @manifest.errors[:directory].empty?
    end

    test "rejects current directory characters" do
      @manifest.directory = "/./././"
      refute @manifest.valid?
      refute @manifest.errors[:directory].empty?
    end

    test "rejects control characters" do
      @manifest.directory = "a\0/b/c"
      refute @manifest.valid?
      refute @manifest.errors[:directory].empty?
    end

    test "allows unicode characters" do
      @manifest.directory = "a/b/é"
      assert @manifest.valid?
      assert @manifest.errors[:directory].empty?
    end

    test "allows space characters" do
      @manifest.directory = "a/b b/c"
      assert @manifest.valid?
      assert @manifest.errors[:directory].empty?
    end

    test "rejects newline characters" do
      @manifest.directory = "a/b\nb/c"
      refute @manifest.valid?
      refute @manifest.errors[:directory].empty?
    end

    test "rejects a .git directory" do
      @manifest.directory = ".git"
      refute @manifest.valid?
      refute @manifest.errors[:directory].empty?
    end

    test "allows a .github directory" do
      @manifest.directory = ".github"
      assert @manifest.valid?
      assert @manifest.errors[:directory].empty?
    end

    test "allows a . directory not in root" do
      @manifest.directory = "app/.storybook"
      assert @manifest.valid?
      assert @manifest.errors[:directory].empty?
    end

    test "rejects a directory called ." do
      @manifest.directory = "app/."
      refute @manifest.valid?
      refute @manifest.errors[:directory].empty?
    end
  end

  context "sanitizing directory path name" do
    test "removes extra directory separators" do
      subject = UploadManifestFile.new(
        repository: @repo,
        directory: "/a/b//c/")
      assert_equal "a/b/c", subject.directory
    end
  end
end
