# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRecommendationOptOutTest < GitHub::TestCase
  context "validations" do
    test "requires a repository" do
      opt_out = RepositoryRecommendationOptOut.new

      refute_predicate opt_out, :valid?
      assert_includes opt_out.errors[:repository], "can't be blank"
    end
  end
end
