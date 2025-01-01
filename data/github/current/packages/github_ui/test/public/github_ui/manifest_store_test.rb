# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubUIManifestStoreTest < GitHub::TestCase
  setup do
    GitHubUI::ManifestStore.clear
  end

  test "creates a new UIManifest" do
    GitHubUI::ManifestStore.set(target: "full", git_sha: "deadbeef", manifest: { foo: "bar" })

    record = UIManifest.find_by(target: "full")
    assert_equal record&.target, "full"
    assert_equal record&.sha, "deadbeef"
    assert_equal record&.manifest, { "foo" => "bar" }
  end

  test "updates existing UIManifest with matching target" do
    UIManifest.create!(target: "full", sha: "deadbeef", manifest: { foo: "bar" })
    GitHubUI::ManifestStore.set(target: "full", git_sha: "sha", manifest: { foo: "baz" })

    record = UIManifest.find_by(target: "full")
    assert_equal record&.target, "full"
    assert_equal record&.sha, "sha"
    assert_equal record&.manifest, { "foo" => "baz" }
  end

  test "gets the sha from the targeted UIManifest" do
    UIManifest.create!(target: "full", sha: "deadbeef", manifest: { foo: "bar" })
    sha = GitHubUI::ManifestStore.get_sha(target: "full")

    assert_equal sha, "deadbeef"
  end

  test "only fetches manifest once from database" do
    record = UIManifest.create!(target: "full", sha: "deadbeef", manifest: { foo: "bar" })

    UIManifest.expects(:find_by).once.returns(record)
    manifest = GitHubUI::ManifestStore.get_manifest(git_sha: "deadbeef")
    GitHubUI::ManifestStore.get_manifest(git_sha: "deadbeef")

    assert_equal manifest, { "foo" => "bar" }
  end
end
