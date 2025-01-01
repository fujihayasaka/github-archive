# typed: true
# frozen_string_literal: true

require "test_helper"

class TreeEntryRenderHelperTest < GitHub::TestCase
  fixtures do
    @viewer = create(:verified_user)
    @repo = create(:repository, owner: @viewer)
  end

  test "does encode the path" do
    path = "foo bar"
    expected = "foo%20bar"

    result = TreeEntryRenderHelper.raw_blob_url(@viewer, @repo, "", path)
    assert_match(expected, result)
  end

  test "does not re-encode when the path is already URL encoded" do
    path = "foo%20bar"
    result = TreeEntryRenderHelper.raw_blob_url(@viewer, @repo, "", path)

    assert_match(path, result)
  end

  test "correctly handles only filenames with a fragment" do
    path = "file.png#some-fragment"
    expected = "\/file\.png#some-fragment"

    result = TreeEntryRenderHelper.raw_blob_url(@viewer, @repo, "master", Array(path).join("/"))

    assert_match(expected, result)
  end

  test "correctly handles directory/filenames with a fragment" do
    path = "testing/file.png#some-fragment"
    expected = "testing\/file\.png#some-fragment"

    result = TreeEntryRenderHelper.raw_blob_url(@viewer, @repo, "master", Array(path).join("/"))

    assert_match(expected, result)
  end

  test "correctly handles a filepath that has a file extension as a directory name and a fragment" do
    path = "testing.js/#file.png"
    expected = "testing\.js\/%23file\.png"

    result = TreeEntryRenderHelper.raw_blob_url(@viewer, @repo, "master", Array(path).join("/"))

    assert_match(expected, result)
  end

  # This logic is currently needed in the goomba pipelines
  test "correctly handles filenames that contain a properly formatted fragment" do
    path = "testing.js/test/image.png#some-fragment"
    expected = "testing\.js\/test\/image\.png#some-fragment"

    result = TreeEntryRenderHelper.raw_blob_url(@viewer, @repo, "master", Array(path).join("/"))
    assert_match(expected, result)
  end

  context ".raw_gist_url" do
    test "with a user" do
      gist = GistHelpers.generate(
        user: @viewer,
        contents: [{
          name: "file.rb",
          value: "puts 'hi'"
        }],
        description: "Public gist"
      )
      content_url = TreeEntryRenderHelper.raw_gist_url(@viewer, gist, gist.sha, "file.rb")
      expected_path = "/gist/#{@viewer}/#{gist.repo_name}/raw/#{gist.sha}/file.rb"
      assert content_url.ends_with?(expected_path)
    end

    test "without a user" do
      gist = GistHelpers.generate(
        user: @viewer,
        contents: [{
          name: "file.rb",
          value: "puts 'hi'"
        }],
        description: "Public gist"
      )
      content_url = TreeEntryRenderHelper.raw_gist_url(nil, gist, gist.sha, "file.rb")
      expected_path = "/gist/#{@viewer}/#{gist.repo_name}/raw/#{gist.sha}/file.rb"
      assert content_url.ends_with?(expected_path)
    end
  end

  test "media blob url should not have double slashes when ref is missing" do
    path = "Untitled.jpg"
    content_url = TreeEntryRenderHelper.media_blob_url(@viewer, @repo, "", path)
    expected_url = "http://alambic.github.test/assets/media/#{@repo.name_with_display_owner}/Untitled.jpg"

    assert_equal expected_url, content_url
  end

  test "media blob url should contain reference and path when present" do
    path = "example/Untitled.jpg"
    content_url = TreeEntryRenderHelper.media_blob_url(@viewer, @repo, "main", path)
    expected_url = "http://alambic.github.test/assets/media/#{@repo.name_with_display_owner}/main/example/Untitled.jpg"

    assert_equal expected_url, content_url
  end

  test "storage cluster url should not have double slashes when ref is missing" do
    path = "Untitled.jpg"
    content_url = TreeEntryRenderHelper.storage_cluster_url(@viewer, @repo, "", path)
    expected_url = "http://alambic.github.test/storage/raw_lfs/#{@repo.name_with_display_owner}/Untitled.jpg"

    assert_equal expected_url, content_url
  end

  test "storage cluster url should contain reference and path when present" do
    path = "example/Untitled.jpg"
    content_url = TreeEntryRenderHelper.storage_cluster_url(@viewer, @repo, "main", path)
    expected_url = "http://alambic.github.test/storage/raw_lfs/#{@repo.name_with_display_owner}/main/example/Untitled.jpg"

    assert_equal expected_url, content_url
  end
end
