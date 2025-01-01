# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class ManifestEnumeratorTest < GitHub::TestCase
  include PushTestHelper

  Spokesd.share_spokesdb(self)

  setup do
    # Spokes needs to be enabled to get the changed files from the Push models
    Spokesd.enable_spokesd

    @user = create(:organization)
    @repository = create(:repository, owner: @user, from_example: :initial_commit_ruby_library)

    @manifest_enumerator = ManifestEnumerator.new
  end

  context "#scan_repository" do
    test "returns empty list for repositories with no manifests" do
      repo = create(:repository, from_example: :simple)
      assert_equal [], @manifest_enumerator.scan_repository(repo, repo.default_oid)
    end

    test "detects manifest files in the repository" do
      manifests = @manifest_enumerator.scan_repository(@repository, @repository.default_oid)
      assert_same_elements ["Gemfile", "initial_commit_ruby_library.gemspec"], manifests.map(&:full_path)

      push_changes(repository: @repository, changes: [
        { path: "js/package.json", content: "{}" },
      ])

      manifests = @manifest_enumerator.scan_repository(@repository, @repository.default_oid)
      assert_same_elements ["Gemfile", "initial_commit_ruby_library.gemspec", "js/package.json"], manifests.map(&:full_path)
      assert_same_elements %w[
        32fd3d48a3fbfc320e42a55553b827626c25ccab
        a542314947ccafbd80a162e3fc650595aa252a63
        9e26dfeeb6e641a33dae4961196235bdb965b21b
      ], manifests.map(&:blob_oid)
    end

    test "sorts manifests by depth and name" do
      push_changes(repository: @repository, changes: [
        { path: "js/package.json", content: '{"name": "lib"}' },
        { path: "package.json", content: '{"name": "app"}' },
        { path: "lib.gemspec", content: "library" },
      ])

      manifests = @manifest_enumerator.scan_repository(@repository, @repository.default_oid).map(&:full_path)
      assert_equal ["Gemfile", "initial_commit_ruby_library.gemspec", "lib.gemspec", "package.json", "js/package.json"], manifests
    end

    test "handles invalid utf8 paths" do
      push_changes(repository: @repository, changes: [
        { path: "\xC8\xF2\x7F\xAF/package.json", content: "{}" },
      ])

      manifests = @manifest_enumerator.scan_repository(@repository, @repository.default_oid).map(&:full_path)
      assert_same_elements ["Gemfile", "initial_commit_ruby_library.gemspec"], manifests
    end
  end

  context "#scan_push" do
    test "persists manifest files that were added" do
      push = push_changes(repository: @repository, changes: [
        { path: "Gemfile", content: "gem 'linguist'" },
        { path: "js/package.json", content: "{}" },
      ])

      changed, removed = @manifest_enumerator.scan_push(push)
      assert_equal ["Gemfile", "js/package.json"], changed.map(&:full_path)
      assert_empty removed
    end

    test "persists manifest files that were removed" do
      push_changes(repository: @repository, changes: [
        { path: "deleteme/package.json", content: "{}" },
      ])
      push = push_changes(repository: @repository, changes: [
        { path: "deleteme/package.json", new_path: nil },
      ])

      changed, removed = @manifest_enumerator.scan_push(push)
      assert_empty changed
      assert_equal ["deleteme/package.json"], removed.map(&:full_path)
    end

    test "truncates list of changed manifests if it exceeds the limit" do
      number_of_manifests = @repository.max_manifest_files * 2
      additions = []
      number_of_manifests.times do |n|
        additions << { path: "#{n}/Gemfile", content: "" }
      end
      push = push_changes(repository: @repository, changes: additions)

      changed, removed = @manifest_enumerator.scan_push(push)
      assert_equal @repository.max_manifest_files, changed.size
      assert_empty removed
    end
  end
end
