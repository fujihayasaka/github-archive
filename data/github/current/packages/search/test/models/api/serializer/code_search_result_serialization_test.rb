# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class CodeSearchResultSerializationTest < GitHub::TestCase
  test "path serialization" do
    repo = build_stubbed(:repository, name: "bar", owner: build_stubbed(:user, login: "foo"))

    result = {
      "_model" => repo,
      "_source" => {
        "path" => nil,
        "filename" => "README.txt",
        "blob_sha" => "ffffffffffffffffffffffffffffffffffffffff",
        "commit_sha" => "cccccccccccccccccccccccccccccccccccccccc",
      }
    }
    hash = Api::Serializer.serialize(:code_search_result_item_hash, result, {})
    assert_equal "README.txt", hash[:name]
    assert_equal "README.txt", hash[:path]
    assert_equal "#{GitHub.api_url}/repositories/#{repo.id}/contents/README.txt?ref=cccccccccccccccccccccccccccccccccccccccc", hash[:url]
    assert_equal "#{GitHub.url}/foo/bar/blob/cccccccccccccccccccccccccccccccccccccccc/README.txt", hash[:html_url]
  end

  test "path serialization with #" do
    repo = build_stubbed(:repository, name: "bar", owner: build_stubbed(:user, login: "foo"))

    result = {
      "_model" => repo,
      "_source" => {
        "path" => "foo/bar#baz",
        "filename" => "#20 README.txt",
        "blob_sha" => "ffffffffffffffffffffffffffffffffffffffff",
        "commit_sha" => "cccccccccccccccccccccccccccccccccccccccc",
      }
    }
    hash = Api::Serializer.serialize(:code_search_result_item_hash, result, {})
    assert_equal "#20 README.txt", hash[:name]
    assert_equal "foo/bar#baz/#20 README.txt", hash[:path]
    assert_equal "#{GitHub.api_url}/repositories/#{repo.id}/contents/foo/bar%23baz/%2320%20README.txt?ref=cccccccccccccccccccccccccccccccccccccccc", hash[:url]
    assert_equal "#{GitHub.url}/foo/bar/blob/cccccccccccccccccccccccccccccccccccccccc/foo/bar%23baz/%2320%20README.txt", hash[:html_url]
  end
end
