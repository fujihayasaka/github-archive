# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class GistSerializersTest < Api::SerializerTestCase
  fixtures do
    @author = create :user, login: "author"
    contents = [{ name: "file.txt", value: "stuff" }]
    @gist = Gist::Creator.create! user: @author, contents: contents, public: true
  end

  context "#gist_hash" do
    test "renders beta format when beta media type is requested" do
      api_media_type "application/vnd.github.beta+json"

      output = gist(@gist)
      assert_equal "author", output["user"]["login"]
      refute output.key?("owner"),
        "Expected beta output to omit 'owner' property"
    end

    test "response includes user property when beta media type is requested and changeset is active" do
      api_media_type "application/vnd.github.beta+json"
      with_changeset "deprecate_beta_media_type" do
        output = gist(@gist)
        assert_equal "author", output["owner"]["login"]
        assert output.key?("user"),
          "Expected v3 output to include 'user' property"
        assert_nil output["user"]
      end
    end

    test "response excludes history property when base-gist changeset is active" do
      with_changeset "remove_forks_history_from_base_gist" do
        output = gist(@gist)
        refute output.key?("history")
      end
    end

    test "response excludes forks property when base-gist changeset is active" do
      with_changeset "remove_forks_history_from_base_gist" do
        output = gist(@gist)
        refute output.key?("forks")
      end
    end

    test "renders v3 format by default" do
      output = gist(@gist)
      assert_equal "author", output["owner"]["login"]
      assert output.key?("user"),
        "Expected v3 output to include 'user' property"
      assert_nil output["user"]
    end

    test "renders forked gist properly" do
      forking_user = create(:user)
      forked_gist = @gist.fork(forking_user)
      new_content = [{ name: "fork.txt", value: "put a fork in it" }]
      forked_gist.commit_contents!(new_content, forking_user)

      output = gist(forked_gist, { full: true })
      assert output.key?("fork_of"), "Expect v3 output to include 'fork_of'"
    end
  end
end
