# typed: true
# frozen_string_literal: true

require "test_helper"

class HasStarredCheckerTest < GitHub::TestCase
  context "#run" do
    test "returns a hash of entity keys and boolean values" do
      user = create(:user)
      topic = create(:topic)
      repo = create(:repository)
      gist = create(:gist)
      user.stars.create(starrable: topic)
      user.gist_stars.create(gist: gist)

      entities = ["Topic:#{topic.id}", "Repository:#{repo.id}", "Gist:#{gist.id}"]
      checker = HasStarredChecker.new(user.id, entities)
      results = checker.run

      expected_results = {
        "Topic:#{topic.id}" => true,
        "Repository:#{repo.id}" => false,
        "Gist:#{gist.id}" => true,
      }
      assert_equal expected_results, results
    end
  end
end
