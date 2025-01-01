# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProject::IssuesGraphDependencyTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @memex = create(:memex_project)
  end

  context "#to_hierarchy_model_key" do
    test "returns a hash representing the @memex key in the hierarchy" do
      result = @memex.to_hierarchy_model_key

      assert_equal @memex.owner_id, result.dig(:ownerId)
      assert_equal @memex.id, result.dig(:itemId)
    end
  end

  context "#to_hierarchy_model" do
    test "returns a hash representing the @memex in the hierarchy" do
      result = @memex.to_hierarchy_model

      assert_equal @memex.owner_id, result.dig(:key, :ownerId)
      assert_equal @memex.id, result.dig(:key, :itemId)
      assert_equal @memex.creator_id, result.dig(:creatorId)
      assert_equal @memex.title, result.dig(:title)
      assert_equal @memex.description, result.dig(:description)
      assert_equal @memex.public, result.dig(:public)
      assert_equal @memex.number, result.dig(:number)
      assert_equal false, result.dig(:userHidden)
      assert_equal @memex.url.to_s, result.dig(:url)
    end

    test "returns nil if owner has been destroyed" do
      @memex.owner.destroy
      @memex.reload

      expected_keys = {
        "Body": "MemexProject#to_hierarchy_model returned nil due to missing owner",
        "code.namespace": "MemexProject::IssuesGraphDependency",
        "code.function": "to_hierarchy_model",
        "gh.memex.project.id": @memex.id,
      }

      assert_logged(**expected_keys) do
        assert_nil @memex.to_hierarchy_model
      end
    end
  end
end
