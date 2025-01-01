# typed: true
# frozen_string_literal: true

require "test_helper"

class Releases::Public::HelperTest < Api::TestCase
  fixtures do
    @repo = create :repository, from_example: :repository_test_simple
    @release = create :release, repository: @repo, tag_name: "v1"
  end

  context ".load_or_build_by_tag" do
    test "finds a release with a database record" do
      release = Releases::Public::Helper.load_or_build_by_tag(@repo, "v1")
      refute T.must(release).new_record?
      refute T.must(release).notes?
      assert T.must(release).viewable?
    end

    test "finds a release with a git tag and no record" do
      assert_equal 1, @repo.releases.count
      release = Releases::Public::Helper.load_or_build_by_tag(@repo, "v2")
      assert_equal 1, @repo.releases.count
      assert T.must(release).new_record?
      refute T.must(release).notes?
      refute T.must(release).viewable?
    end

    test "fails correctly on non-existent git tag" do
      assert_nil Releases::Public::Helper.load_or_build_by_tag(@release.repository, "noooope")
    end
  end
end
