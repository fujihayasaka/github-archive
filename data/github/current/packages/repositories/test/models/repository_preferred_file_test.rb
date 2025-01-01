# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPreferredFileTest < GitHub::TestCase
  def repo_with_file(path, branch: "master")
    repo = create(:repository, from_example: :simple)
    repo.heads.create(branch, repo.heads.find("master").target, repo.owner) if branch != "master"

    ref = repo.heads.find(branch)
    metadata = { committer: repo.owner, message: "add #{path}" }

    ref.append_commit(metadata, repo.owner) do |files|
      files.add(path.to_s, "some content")
    end

    repo
  end

  context "named preferred files methods" do
    [:code_of_conduct, :contributing, :readme, :support, :issue_template, :pull_request_template].each do |type|
      test "finds plaintext #{type} files" do
        repo = repo_with_file(type)
        preferred_tree_entry = repo.public_send("preferred_#{type}".to_sym)
        assert preferred_tree_entry
        assert_equal type.to_s, preferred_tree_entry.path
      end

      test "finds markdown #{type} files" do
        repo = repo_with_file("#{type}.md")
        preferred_tree_entry = repo.public_send("preferred_#{type}".to_sym)
        assert preferred_tree_entry
        assert_equal "#{type}.md", preferred_tree_entry.path
      end

      test "finds #{type} files in .github" do
        repo = repo_with_file(".github/#{type}")
        preferred_tree_entry = repo.public_send("preferred_#{type}".to_sym)
        assert preferred_tree_entry
        assert_equal ".github/#{type}", preferred_tree_entry.path
      end

      test "finds #{type} files in docs" do
        repo = repo_with_file("docs/#{type}")
        preferred_tree_entry = repo.public_send("preferred_#{type}".to_sym)
        assert preferred_tree_entry
        assert_equal "docs/#{type}", preferred_tree_entry.path
      end

      test "returns nil for preferred_#{type} for an empty repo" do
        repo = create(:repository, from_example: :empty)
        assert_nil repo.public_send("preferred_#{type}".to_sym)
      end

      test "returns nil when no #{type} file exists" do
        repo = repo_with_file("foo.md")
        assert_nil repo.public_send("preferred_#{type}".to_sym)
      end
    end
  end

  context "preferred_license" do
    test "finds plaintext license files" do
      repo = repo_with_file("license.txt")
      assert repo.preferred_license
      assert_equal "license.txt", repo.preferred_license.path
    end

    test "finds markdown license files" do
      repo = repo_with_file("license.md")
      assert repo.preferred_license
      assert_equal "license.md", repo.preferred_license.path
    end

    test "finds license files in the non-default branch when specified" do
      repo = repo_with_file("license.txt", branch: "non-default")
      assert repo.preferred_license(tree_name: "non-default")
      assert_nil repo.preferred_license # On the default branch there is no license.
      assert_equal("license.txt", repo.preferred_license(tree_name: "non-default").path)
    end

    test "does not find license files in .github" do
      repo = repo_with_file(".github/license.md")
      assert_nil repo.preferred_license
    end

    test "does not find license files in docs" do
      repo = repo_with_file("docs/license.md")
      assert_nil repo.preferred_license
    end

    test "returns nil for an empty repo" do
      repo = create(:repository, from_example: :empty)
      assert_nil repo.preferred_license
    end

    test "returns nil when no license file exists" do
      repo = repo_with_file("foo.md")
      assert_nil repo.preferred_license
    end
  end
end
