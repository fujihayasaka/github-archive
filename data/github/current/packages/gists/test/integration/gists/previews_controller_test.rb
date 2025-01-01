# typed: true
# frozen_string_literal: true

require "test_helper"

class Gists::PreviewsControllerTest < GitHub::IntegrationTestCase

  skip_in_multitenant_mode

  include HydroTestHelpers

  RAW = <<~MD
    > aaa
    > bbb
    > ccc

    :gem: feature
  MD
  FORMATTED = <<~HTML
    <blockquote>
    <p>aaa
    bbb
    ccc</p>
    </blockquote>
    <p>💎 feature</p>
  HTML

  fixtures do
    @user = create :user
  end

  test "formats content" do
    as @user
    post "gist/gists/previews", params: {
      code: RAW,
      blobname: "file.md"
    }

    assert_response :ok
    assert_equal FORMATTED, response.body
  end

  test "allows anonymous when enabled" do
    GitHub.override(:anonymous_gist_creation_enabled, true) do
      post "gist/gists/previews", params: {
        code: RAW,
        blobname: "file.md"
      }

      assert_response :ok
      assert_equal FORMATTED, response.body
    end
  end

  test "allows user when anonymous is enabled" do
    GitHub.override(:anonymous_gist_creation_enabled, true) do
      as @user
      post "gist/gists/previews", params: {
        code: RAW,
        blobname: "file.md"
      }

      assert_response :ok
      assert_equal FORMATTED, response.body
    end
  end

  test "denies anonymous when disabled" do
    GitHub.override(:anonymous_gist_creation_enabled, false) do
      post "gist/gists/previews", params: {
        code: RAW,
        blobname: "file.md"
      }

      assert_response :forbidden
    end
  end

  test "allows user when anonymous is disabled" do
    GitHub.override(:anonymous_gist_creation_enabled, false) do
      as @user
      post "gist/gists/previews", params: {
        code: RAW,
        blobname: "file.md"
      }

      assert_response :ok
      assert_equal FORMATTED, response.body
    end
  end
end
