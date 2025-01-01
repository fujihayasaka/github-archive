# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class TagsPublicTest < Api::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)

    %w(refs/tags/2.0-release refs/tags/1.0-release).each do |name|
      Git::Ref.new(@repo, name).create(@repo.default_oid, @repo.owner)
    end
  end

  setup do
    Spokesd.enable_spokesd
  end

  context ".sorted_for" do
    test "returns all existing tags sorted" do
      refs = Tags::Public.sorted_for(repository: @repo, pattern: nil)

      assert_equal 4, refs.size
      assert_equal ["v1", "v2", "1.0-release", "2.0-release"], refs.map { |ref| ref[0].gsub("refs/tags/", "") }
    end

    test "returns existing tags sorted matching a pattern" do
      refs = Tags::Public.sorted_for(repository: @repo, pattern: "2")

      assert_equal 2, refs.size
      assert_equal ["v2", "2.0-release"], refs.map { |ref| ref[0].gsub("refs/tags/", "") }
    end

    test "returns existing tags sorted matching a pattern with *" do
      refs = Tags::Public.sorted_for(repository: @repo, pattern: "*2")

      assert_equal 2, refs.size
      assert_equal ["v2", "2.0-release"], refs.map { |ref| ref[0].gsub("refs/tags/", "") }
    end

    test "returns existing tags sorting missing commit times first" do
      repo = create(:repository, from_example: :tag_without_time)

      refs = Tags::Public.sorted_for(repository: repo, pattern: nil)

      assert_equal 1, refs.size
      assert_equal ["v0.99"], refs.map { |ref| ref[0].gsub("refs/tags/", "") }
    end
  end
end
