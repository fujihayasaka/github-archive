# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class StatusSerializersTest < Api::SerializerTestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)
    @status = create :status, repository: @repo,
      sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
      state: "success",
      creator: @repo.owner,
      target_url: "http://example.org",
      description: "a test description",
      context: "a context"
  end

  context "#status" do
    test "serializes a commit status" do
      output = T.unsafe(self).status(@status)
      assert_equal "success", output["state"]
      assert_equal "http://example.org", output["target_url"]
      assert_equal "a context", output["context"]
      assert_equal "a test description", output["description"]
    end
  end
end
