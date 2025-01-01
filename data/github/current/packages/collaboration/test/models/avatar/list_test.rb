# typed: true
# frozen_string_literal: true

require "test_helper"

class AvatarListTest < GitHub::TestCase
  include CdnTestHelper

  fixtures do
    @user = create(:user)
    @owner = create :oauth_application, user: @user

    meta = {
      content_type: "image/png",
      size: 1,
      width: 100,
      height: 100,
      owner_id: @owner.id,
      owner_type: "OauthApplication",
    }

    @avatar = Avatar.upload(@user, Sham.sha256, meta)
  end

  setup do
    @list = Avatar::List.new(@owner)
  end

  test "builds list containing only an identicon if avatar is quarantined" do
    @avatar.update(quarantined: true)

    modified_at = Time.now
    travel_to modified_at do
      PrimaryAvatar.set @avatar, @user
    end

    items = @list.items
    assert_equal 1, items.size

    assert item = items.shift
    assert_equal "identicon", item[:name]
    assert_equal 31557600, item[:max_age]
  end

  test "builds avatar item list for owner with no avatars" do
    items = @list.items
    assert_equal 1, items.size

    assert item = items.shift
    assert_equal "identicon", item[:name]
    assert_equal 31557600, item[:max_age]
  end

  test "builds avatar item list for user with avatar" do
    modified_at = Time.now
    travel_to modified_at do
      PrimaryAvatar.set @avatar, @user
    end

    items = @list.items
    assert_equal 2, items.size

    assert item = items.shift
    assert_equal "avatar", item[:name]
    assert_media_uri @avatar, item[:url], modified_at
    assert_equal 31557600, item[:max_age]

    assert item = items.shift
    assert_equal "identicon", item[:name]
    assert_equal 31557600, item[:max_age]
  end

  test "build avatar item list with internal identicon url" do
    items = @list.items
    assert item = items.last
    if GitHub.fips_mode?
      assert_equal 64, @list.instance_variable_get(:@owner).identicon_id.size
    else
      assert_equal 32, @list.instance_variable_get(:@owner).identicon_id.size
    end
    assert_equal "identicon", item[:name]
    assert_equal "identicon:/#{@owner.identicon_id}.png", item[:url]
  end

  test "builds avatar url for user with avatar" do
    modified_at = Time.now
    travel_to modified_at do
      PrimaryAvatar.set @avatar, @user
    end

    assert_media_uri @avatar, @list.avatar_template, modified_at
  end

  test "does not error when avatar is not set" do
    assert_nil @list.avatar_template
  end

  test "purges cdn" do
    PrimaryAvatar.set @avatar, @user
    assert_purged_keys Avatar::List.surrogate_key(@owner) do
      assert_nil @list.purge_cdn
    end
  end

  test "surrogate_key size" do
    if GitHub.fips_mode?
      assert_match /oauth_application\/[0-9a-f]{64}\/avatars/, Avatar::List.surrogate_key(@owner)
    else
      assert_match /oauth_application\/[0-9a-f]{40}\/avatars/, Avatar::List.surrogate_key(@owner)
    end
  end

  test "surrogate_keys are unique" do
    # two different types with the same id
    @owner.id = 1
    @user.id = 1
    refute_equal Avatar::List.surrogate_key(@owner), Avatar::List.surrogate_key(@user)

    # two different ids with the same type
    other_app = create :oauth_application
    refute_equal Avatar::List.surrogate_key(@owner), Avatar::List.surrogate_key(other_app)
  end

  def assert_media_uri(avatar, actual_url, modified_at)
    media_re = /\Amedia:\//
    assert_match media_re, actual_url
    path_and_query = actual_url.gsub(media_re, "")
    path, querystring = path_and_query.split("?")
    query = Rack::Utils.parse_query(querystring)

    expected_query = avatar.alambic_internal_media_query
    expected_query.delete(:last_mod)

    assert_equal "#{GitHub.alambic_path_prefix}/#{avatar.asset.oid}", path
    assert_equal "{size}", query["s"]
    assert_equal modified_at.to_i, query["last_mod"].to_i
    expected_query.each do |key, value|
      assert_equal value, query[key.to_s]
    end
    assert_equal expected_query.size + 2, query.size
  end
end
