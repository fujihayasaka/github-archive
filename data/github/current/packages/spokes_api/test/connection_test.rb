# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class SpokesAPIConnectionTest < GitHub::TestCase
  setup do
    Spokesd.enable_spokesd
  end

  fixtures do
    @repo = create :repository, from_example: :repository_test_simple
  end

  def test_connection
    conn = SpokesAPI::Connection.connection
    refute_nil conn

    headers = {
      "Content-Type": "application/json"
    }
    body = {
      repository: { id: @repo.id, type: 1 },
      by_id: { id: "422c2b7ab3b3c668038da977e4e93a5fc623169c" },
    }

    res = conn.post("/twirp/github.spokes.blobs.v1.BlobsAPI/GetBlobContents", body.to_json, headers)
    assert_equal 200, res.status
    assert_equal "application/json", res.headers["Content-Type"]
    data = GitHub::JSON.decode(res.body)
    assert_equal 4, data["size"].to_i
    contents = Base64.decode64(data["contents"])
    assert_equal "a\nb\n", contents
  end
end
