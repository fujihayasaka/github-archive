# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAvatarsTest < GitHub::TestCase
  include CdnTestHelper

  fixtures do
    @user_with_gravatar = create(:user)
    @user_with_gravatar.gravatar_email = "air@bender.me"
    @user_with_gravatar.save!

    @user_no_gravatar = create(:user)
    @user_no_gravatar.gravatar_email = nil
    @user_no_gravatar.save!

    @user_with_avatar = create(:user)

    meta = {
      content_type: "image/png",
      size: 1,
      width: 100,
      height: 100,
      owner_id: @user_with_avatar.id,
      owner_type: "User",
    }

    @avatar = Avatar.upload(@user_with_avatar, Sham.sha256, meta)
    PrimaryAvatar.set @avatar, @user_with_avatar
  end

  test "builds list with gravatar and identicon if avatar is nil" do
    # This should not happen unless Avatars were directly deleted from the database
    @user_with_avatar.primary_avatar.avatar = nil

    items = @user_with_avatar.avatar_list.items
    assert_equal 2, items.size

    assert item = items.shift
    assert_equal "gravatar", item[:name]
    assert_equal 3600, item[:max_age]

    assert item = items.shift
    assert_equal "identicon", item[:name]
    assert_equal 31557600, item[:max_age]
  end

  test "builds list with gravatar and identicon if avatar is quarantined" do
    @avatar.update(quarantined: true)

    items = @user_with_avatar.avatar_list.items
    assert_equal 2, items.size

    assert item = items.shift
    assert_equal "gravatar", item[:name]
    assert_equal 3600, item[:max_age]

    assert item = items.shift
    assert_equal "identicon", item[:name]
    assert_equal 31557600, item[:max_age]
  end

  test "builds list with only identicon if avatar is nil in multi tenant" do
    on_multi_tenant_enterprise do
      # This should not happen unless Avatars were directly deleted from the database
      @user_with_avatar.primary_avatar.avatar = nil

      items = @user_with_avatar.avatar_list.items
      assert_equal 1, items.size

      assert item = items.shift
      assert_equal "identicon", item[:name]
      assert_equal 31557600, item[:max_age]
    end
  end

  test "builds list with only identicon if avatar is quarantined in multi tenant" do
    on_multi_tenant_enterprise do
      @avatar.update(quarantined: true)

      items = @user_with_avatar.avatar_list.items
      assert_equal 1, items.size

      assert item = items.shift
      assert_equal "identicon", item[:name]
      assert_equal 31557600, item[:max_age]
    end
  end

  test "builds avatar item list for user with no avatars" do
    items = @user_no_gravatar.avatar_list.items
    assert_equal 1, items.size

    assert item = items.shift
    assert_equal "identicon", item[:name]
    assert_equal 31557600, item[:max_age]
  end

  test "builds avatar item list for user with only gravatar" do
    items = @user_with_gravatar.avatar_list.items
    assert_equal 2, items.size

    assert item = items.shift
    assert_equal "gravatar", item[:name]
    assert_equal 3600, item[:max_age]

    assert item = items.shift
    assert_equal "identicon", item[:name]
    assert_equal 31557600, item[:max_age]
  end

  test "builds avatar item list for user without gravatar in multi tenant" do
    on_multi_tenant_enterprise do
      items = @user_with_gravatar.avatar_list.items
      assert_equal 1, items.size

      assert item = items.shift
      assert_equal "identicon", item[:name]
      assert_equal 31557600, item[:max_age]
    end
  end

  test "builds avatar item list for user with avatar" do
    items = @user_with_avatar.avatar_list.items
    assert_equal 2, items.size

    assert item = items.shift
    assert_equal "avatar", item[:name]
    assert_media_uri @avatar, item[:url]
    assert_equal 31557600, item[:max_age]

    assert item = items.shift
    assert_equal "identicon", item[:name]
    assert_equal 31557600, item[:max_age]
  end

  test "build avatar item list with internal identicon url" do
    user = @user_with_avatar
    items = user.avatar_list.items
    assert item = items.last
    assert_equal "identicon", item[:name]
    assert_equal "identicon:/#{user.identicon_id}.png", item[:url]
  end

  test "attempts to build avatar url for new user" do
    assert_nil @user_with_gravatar.avatar_list.avatar_template
  end

  test "builds avatar url for user with avatar" do
    assert_media_uri @avatar, @user_with_avatar.avatar_list.avatar_template
  end

  test "builds identicons url" do
    user = @user_with_gravatar
    assert_match user.identicon_id, user.avatar_list.identicons_url
  end

  test "builds user gravatar url" do
    user = @user_with_gravatar
    gid = "4a5360e1d8abada3378e40f45dc76b80"
    uri = URI.parse user.avatar_list.gravatar_url(123)
    query = Rack::Utils.parse_query(uri.query)

    assert_equal "/avatar/#{gid}", uri.path
    assert_equal "123", query["s"]
    assert_equal user.avatar_list.identicons_url, query["d"]
  end

  test "builds gravatar url for user without a gravatar email" do
    user = @user_no_gravatar
    assert_equal user.avatar_list.identicons_url, user.avatar_list.gravatar_url(1)
  end

  test "builds gravatar url for gravatar id only" do
    user = @user_with_gravatar
    avatars = User::AvatarList.with_gravatar_id(user.gravatar_id)
    uri = URI.parse avatars.gravatar_url(5)
    query = Rack::Utils.parse_query(uri.query)

    assert_equal "/avatar/#{user.gravatar_id}", uri.path
    assert_equal "5", query["s"]
    assert_equal User::AvatarList.default_image_url, query["d"]
  end

  test "builds gravatar url for user with blank gravatar_id" do
    user = @user_no_gravatar
    user.gravatar_email = ""
    assert_equal user.avatar_list.identicons_url, user.avatar_list.gravatar_url(1)
  end

  test "builds default image" do
    uri = URI.parse User::AvatarList.default_image_url(123)
    assert_match "/images/gravatars/123.png", uri.path, uri.to_s
  end

  test "builds gravatar url with nil size" do
    email = "user@email.com"
    uri = URI.parse User::AvatarList.gravatar_url_for(email, nil)
    query = Rack::Utils.parse_query(uri.query)
    assert_nil query["s"]
  end

  test "builds gravatar url with 0 size" do
    email = "user@email.com"
    uri = URI.parse User::AvatarList.gravatar_url_for(email, 0)
    query = Rack::Utils.parse_query(uri.query)
    assert_nil query["s"]
  end

  test "builds gravatar url for email with static default image" do
    email = "user@email.com"
    uri = URI.parse User::AvatarList.gravatar_url_for(email, 50, default: "default")
    query = Rack::Utils.parse_query(uri.query)
    default = URI.parse query["d"]

    assert_equal "/avatar/b58c6f14d292556214bd64909bcdb118", uri.path
    assert_equal "50", query["s"]
    assert_match "/images/gravatars/default.png", default.path
  end

  test "builds gravatar url for email with full url default" do
    email = "user@email.com"
    default = "http://default!"
    uri = URI.parse User::AvatarList.gravatar_url_for(email, 50, default: default)
    query = Rack::Utils.parse_query(uri.query)

    assert_equal "/avatar/b58c6f14d292556214bd64909bcdb118", uri.path
    assert_equal "50", query["s"]
    assert_equal default, query["d"]
  end

  test "purges cdn" do
    user = @user_with_avatar

    assert_purged_keys User::AvatarList.surrogate_key(user) do
      assert_nil user.avatar_list.purge_cdn
    end
  end

  test "purges cdn without cdn config" do
    @user_with_avatar.avatar_list.purge_cdn
  end


  def assert_media_uri(avatar, actual_url)
    assert_match MEDIA_URI_RE, actual_url
    path_and_query = actual_url.gsub(MEDIA_URI_RE, "")
    path, querystring = path_and_query.split("?")
    query = Rack::Utils.parse_query(querystring)

    expected_query = avatar.alambic_internal_media_query

    assert_equal "#{GitHub.alambic_path_prefix}/#{avatar.asset.oid}", path
    assert_equal "{size}", query["s"]
    assert_in_delta expected_query.delete(:last_mod), query["last_mod"].to_i, 2
    expected_query.each do |key, value|
      assert_equal value, query[key.to_s]
    end
    assert_equal expected_query.size + 2, query.size
  end

  MEDIA_URI_RE = /\Amedia:\//
end
