# typed: true
# frozen_string_literal: true

require "test_helper"

module AssetScannerHelpers
  def cdn_prod_data_s3_url(user_id, asset_id, guid)
    "https://user-images-cdn.githubusercontent.com/#{user_id}/#{asset_id}-#{guid}.gif"
  end

  def cdn_prod_data_private_images_s3_url(user_id, asset_id, guid)
    "https://private-user-images.githubusercontent.com/#{user_id}/#{asset_id}-#{guid}.gif"
  end

  def canonical_url(user_id, guid)
    "#{GitHub.url}/acme/widgets/assets/#{user_id}/#{guid}"
  end

  def new_canonical_url(guid)
    "#{GitHub.url}/user-attachments/assets/#{guid}"
  end

  def storage_url(user_id, guid)
    "#{GitHub.storage_cluster_url}/user/#{user_id}/files/#{guid}"
  end

  def cloud_asset_url(user_id, asset_id, guid)
    url = "https://x.cloud.github.com/assets/%d/%d/%s.gif" % [
      user_id, asset_id, guid]
  end

  def usercontent_asset_url(user_id, asset_id, guid)
    url = "https://cloud.githubusercontent.com/assets/%d/%d/%s.gif" % [
      user_id, asset_id, guid]
  end

  def s3_asset_url(user_id, asset_id, guid)
    url = "#{GitHub.s3_asset_host}assets/%d/%d/%s.gif" % [
      user_id, asset_id, guid]
  end

  def old_asset_url(user_id, guid)
    url = "https://s3.amazonaws.com/github/assets/%d/%s/%s/%s.gif" % [
      user_id, guid[0, 2], guid[2, 2], guid]
  end

  def file_asset_url(user_id, asset_id, guid)
    parts = [GitHub.asset_base_path]
    parts.push(*("%08d" % user_id).scan(/..../))
    parts.push(*("%08d" % asset_id).scan(/..../))
    parts << (guid + ".")

    case GitHub.file_asset_host
    when "", "/", nil
      "/#{parts.join("/")}"
    else
      "#{GitHub.file_asset_host}/#{parts.join("/")}"
    end
  end

  def scan(markdown, pipe = GitHub::Goomba::MarkdownPipeline)
    content = GitHub::HTML::BodyContent.new(markdown, {}, pipe)
    AssetScanner.build(content.document)
  end
end

class AssetScannerWithClusterEnabledTest < GitHub::TestCase
  include AssetScannerHelpers

  setup do
    GitHub.storage_cluster_enabled = true
    GitHub.s3_uploads_enabled = false
  end

  def with_storage_urls
    user_id = 12345
    guid = SecureRandom.uuid

    [
      storage_url(user_id, guid),
      "#{GitHub.storage_cluster_url}/user-1/repo-2/assets/#{user_id}/#{guid}"
    ].each { |url| yield(url, user_id, guid) }
  end

  test "parses from new storage URL in html" do
    guid = SecureRandom.uuid
    scanner = scan("![](#{GitHub.url}/user-attachments/assets/#{guid})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.cluster_asset_re.inspect, scanner.doc]
    assert_nil match.user_id
    assert_nil match.asset_id
    assert_equal guid, match.asset_guid
  end

  test "parses from new storage url" do
    guid = SecureRandom.uuid
    mres = AssetScanner.check_url("#{GitHub.url}/user-attachments/assets/#{guid}")
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_nil mres.match.user_id
    assert_nil mres.match.asset_id
    assert_equal guid, mres.match.asset_guid
  end

  test "parses from storage url in html" do
    with_storage_urls do |url, user_id, guid|
      scanner = scan("![](#{url})")
      assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.cluster_asset_re.inspect, scanner.doc]
      assert_equal "#{user_id}", match.user_id
      assert_nil match.asset_id
      assert_equal guid, match.asset_guid
    end
  end

  test "parses from storage url" do
    with_storage_urls do |url, user_id, guid|
      mres = AssetScanner.check_url(url)
      refute_nil mres
      assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
      assert_equal "#{user_id}", mres.match.user_id
      assert_nil mres.match.asset_id
      assert_equal guid, mres.match.asset_guid
    end
  end

  test "parses from file url in html" do
    scanner = scan("![](#{file_asset_url(12345, 54321, "abcde")})")
    match = scanner.matches.first
    if GitHub.enterprise?
      assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.file_asset_re.inspect, scanner.doc]
      assert_equal "12345", match.user_id
      assert_equal "54321", match.asset_id
      assert_equal "abcde", match.asset_guid
    else
      assert_nil match
    end
  end

  test "parses from file url" do
    mres = AssetScanner.check_url(file_asset_url(12345, 54321, "abcde"))
    refute_nil mres
    if GitHub.enterprise?
      assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
      assert_equal "12345", mres.match.user_id
      assert_equal "54321", mres.match.asset_id
      assert_equal "abcde", mres.match.asset_guid
    else
      refute mres.success?, "should not have matched: #{mres.match.inspect}"
    end
  end
end

class AssetScannerWithS3EnabledTest < GitHub::TestCase
  include AssetScannerHelpers

  setup do
    GitHub.storage_cluster_enabled = false
    GitHub.s3_uploads_enabled = true
    GitHub.user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
    GitHub.private_user_images_cdn_url = "https://private-user-images.githubusercontent.com"
  end

  teardown do
    GitHub.user_images_cdn_url = nil
    GitHub.private_user_images_cdn_url = nil
  end

  test "parses from production data cdn url in html" do
    scanner = scan("![](#{cdn_prod_data_s3_url(1, 2, "abcde")})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.cdn_prod_data_s3_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_equal "2", match.asset_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses from production data cdn url" do
    mres = AssetScanner.check_url(cdn_prod_data_s3_url(1, 2, "abcde"))
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_equal "1", mres.match.user_id
    assert_equal "2", mres.match.asset_id
    assert_equal "abcde", mres.match.asset_guid
  end

  test "parses from storage url when private user images CDN is nil" do
    GitHub.stubs(:include_alambic_asset_storage_paths?).returns(true)
    GitHub.private_user_images_cdn_url = nil

    mres = AssetScanner.check_url(cdn_prod_data_private_images_s3_url(1, 2, "abcde"))
    refute_nil mres
  end

  test "parses from production data private images cdn url in html" do
    scanner = scan("![](#{cdn_prod_data_private_images_s3_url(1, 2, "abcde")})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.cdn_prod_data_private_images_s3_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_equal "2", match.asset_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses from production data private images cdn url" do
    mres = AssetScanner.check_url(cdn_prod_data_private_images_s3_url(1, 2, "abcde"))
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_equal "1", mres.match.user_id
    assert_equal "2", mres.match.asset_id
    assert_equal "abcde", mres.match.asset_guid
  end

  test "parses from canonical url in html" do
    scanner = scan("![](#{canonical_url(1, "abcde")})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.canonical_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses from new canonical url in html" do
    guid = SecureRandom.uuid
    scanner = scan("![](#{new_canonical_url(guid)})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.new_canonical_re.inspect, scanner.doc]
    assert_equal guid, match.asset_guid
  end

  test "parses from cannonical url" do
    mres = AssetScanner.check_url(canonical_url(1, "abcde"))
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_equal "1", mres.match.user_id
    assert_equal "abcde", mres.match.asset_guid
  end

  test "parses from new canonical url" do
    guid = SecureRandom.uuid
    mres = AssetScanner.check_url(new_canonical_url(guid))
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_equal guid, mres.match.asset_guid
  end

  test "parses video from production data private images cdn url in html" do
    scanner = scan("<video src='#{cdn_prod_data_private_images_s3_url(1, 2, "abcde")}'></video>", GitHub::Goomba::MarkdownPipeline)
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.cdn_prod_data_private_images_s3_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_equal "2", match.asset_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses from usercontent url in html" do
    scanner = scan("![](#{usercontent_asset_url(1, 2, "abcde")})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.legacy_usercontent_asset_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_equal "2", match.asset_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses video from usercontent url in html" do
    scanner = scan("<video src='#{usercontent_asset_url(1, 2, "abcde")}'></video>", GitHub::Goomba::MarkdownPipeline)
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.legacy_usercontent_asset_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_equal "2", match.asset_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses from usercontent url" do
    mres = AssetScanner.check_url(usercontent_asset_url(1, 2, "abcde"))
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_equal "1", mres.match.user_id
    assert_equal "2", mres.match.asset_id
    assert_equal "abcde", mres.match.asset_guid
  end

  test "parses from cloud url in html" do
    scanner = scan("![](#{cloud_asset_url(1, 2, "abcde")})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.old_cloud_asset_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_equal "2", match.asset_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses from cloud url" do
    mres = AssetScanner.check_url(cloud_asset_url(1, 2, "abcde"))
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_equal "1", mres.match.user_id
    assert_equal "2", mres.match.asset_id
    assert_equal "abcde", mres.match.asset_guid
  end

  test "parses from s3 url in html" do
    scanner = scan("![](#{s3_asset_url(1, 2, "abcde")})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.legacy_s3_asset_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_equal "2", match.asset_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses from s3 url" do
    mres = AssetScanner.check_url(s3_asset_url(1, 2, "abcde"))
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_equal "1", mres.match.user_id
    assert_equal "2", mres.match.asset_id
    assert_equal "abcde", mres.match.asset_guid
  end

  test "parses from old url in html" do
    scanner = scan("![](#{old_asset_url(1, "abcde")})")
    assert match = scanner.matches.first, "Content does not match regex: %s\n%s" % [scanner.old_asset_re.inspect, scanner.doc]
    assert_equal "1", match.user_id
    assert_nil match.asset_id
    assert_equal "abcde", match.asset_guid
  end

  test "parses from old url" do
    mres = AssetScanner.check_url(old_asset_url(1, "abcde"))
    refute_nil mres
    assert mres.success?, "bad patterns: #{mres.patterns.inspect}"
    assert_equal "1", mres.match.user_id
    assert_nil mres.match.asset_id
    assert_equal "abcde", mres.match.asset_guid
  end

  test "finds matching old images in html" do
    scanner = scan("![](#{old_asset_url(1, "abcde")}) ![](foo.jpg)")
    assert_equal 1, scanner.matches.size, scanner.matches.inspect
  end
end
