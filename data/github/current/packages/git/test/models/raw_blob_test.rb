# typed: true
# frozen_string_literal: true

require "test_helper"

class RawBlobTest < GitHub::TestCase
  fixtures do
    @user = create(:user,
      login: "fake",
      email: "fake@github.com",
      plan: "small",
    )

    @public_repo = create(:public_repository, owner: @user, name: "simple-repo")

    @session = create(:user_session, user: @user)

    @installation = make_integration_installation(target: @user, permissions: { "metadata" => :read })
  end

  test "should return a valid scope string" do
    scope = RawBlob.scope(@public_repo, "some_ref", "some/path")
    assert_equal "RawBlob:fake/simple-repo/some_ref/some/path", scope
  end

  test "should return a valid scope string when given binary encoded data" do
    ref = "删除课程"
    path = "some/删除课程"

    scope = RawBlob.scope(@public_repo, ref.b, path.b)

    assert_equal "RawBlob:fake/simple-repo/#{ref}/#{path}", scope
  end

  test "token for invalid expires key" do
    scope = RawBlob.scope(@public_repo, "some_ref", "some/path")

    assert_raises(ArgumentError) do
      RawBlob.token(@public_repo, scope, :invalid, session: @session)
    end
  end

  test "token for raw blob" do
    @user.update!(plan: "free")
    # Public repo
    scope = RawBlob.scope(@public_repo, "some_ref", "some/path")

    Timecop.freeze do
      GitHub::Authentication::SignedAuthToken.expects(:generate).with(scope: scope, session: @session, user: nil, expires: 1.week.from_now, data: nil)
      token = RawBlob.token(@public_repo, scope, :blob, session: @session)
    end

    # Private repo
    priv_repo = create :private_repository, owner: @user, name: "priv"
    scope = RawBlob.scope(priv_repo, "some_ref", "some/path")

    Timecop.freeze do
      GitHub::Authentication::SignedAuthToken.expects(:generate).with(scope: scope, session: @session, user: nil, expires: 60.seconds.from_now, data: nil)
      RawBlob.token(priv_repo, scope, :blob, session: @session)
    end

    @user.update!(plan: "pro")
    Timecop.freeze do
      GitHub::Authentication::SignedAuthToken.expects(:generate).with(scope: scope, session: @session, user: nil, expires: 1.hour.from_now, data: nil)
      RawBlob.token(priv_repo, scope, :blob, session: @session)
    end

    # Public repo, pro plan
    Timecop.freeze do
      GitHub::Authentication::SignedAuthToken.expects(:generate).with(scope: scope, session: @session, user: nil, expires: 1.week.from_now, data: nil)
      token = RawBlob.token(@public_repo, scope, :blob, session: @session)
    end
  end

  test "token for raw :render" do
    scope = RawBlob.scope(@public_repo, "some_ref", "some/path")

    Timecop.freeze do
      GitHub::Authentication::SignedAuthToken.expects(:generate).with(scope: scope, session: @session, user: nil, expires: 60.seconds.from_now, data: nil)
      RawBlob.token(@public_repo, scope, :render, session: @session)
    end
  end

  test "token can be tied to current user session" do
    scope = RawBlob.scope(@public_repo, "some_ref", "some/path")

    Timecop.freeze do
      new_session = create(:user_session, user: @user)
      token = RawBlob.token(@public_repo, scope, :blob, session: new_session)

      assert_predicate GitHub::Authentication::SignedAuthToken.verify(token: token, scope: scope), :valid?

      new_session.revoke("logout")
      refute_predicate GitHub::Authentication::SignedAuthToken.verify(token: token, scope: scope), :valid?
    end
  end

  test "token can be tied to current user" do
    scope = RawBlob.scope(@public_repo, "some_ref", "some/path")

    Timecop.freeze do
      token = RawBlob.token(@public_repo, scope, :blob, user: @user)

      assert_predicate GitHub::Authentication::SignedAuthToken.verify(token: token, scope: scope), :valid?
    end
  end

  test "token for a bot should be tied to the installation" do
    scope = RawBlob.scope(@public_repo, "some_ref", "some/path")

    Timecop.freeze do
      token = RawBlob.token(@public_repo, scope, :blob, user: @installation.bot)

      result = GitHub::Authentication::SignedAuthToken.verify(token: token, scope: scope)

      assert_predicate result, :valid?
      assert_equal @installation.id, result.installation_id
      assert_equal @installation.class.to_s, result.installation_type
    end
  end
end

class RawBlobContentHelpersTest < GitHub::TestCase
  include RawBlob::ContentHelpers

  test "mime_for path" do
    assert_equal "image/png", mime_for("foo.png")
    assert_equal "application/zip", mime_for("foo.zip")
    assert_equal "application/ruby", mime_for("foo.rb")
    assert_equal "text/plain", mime_for("foo.txt")
    assert_equal "video/mp2t", mime_for("foo.ts")
    assert_equal "video/vnd.nokia.interleaved-multimedia", mime_for("foo.nim")
  end

  test "raw_mime_for path" do
    assert_equal "image/png", raw_mime_for("foo.png")
    assert_equal "application/zip", raw_mime_for("foo.zip")
    assert_equal "application/octet-stream", raw_mime_for("foo.rb")
    assert_equal "text/plain", raw_mime_for("foo.txt")
    assert_equal "video/mp2t", raw_mime_for("foo.ts")
    assert_equal "video/vnd.nokia.interleaved-multimedia", raw_mime_for("foo.nim")
    assert_equal "text/plain", raw_mime_for("foo.ts", is_text: true)
    assert_equal "text/plain", raw_mime_for("foo.nim", is_text: true)
  end

  test "convert mime for raw requests" do
    assert_equal "text/plain", raw_mime("text/plain")
    assert_equal "text/plain; charset=utf-8", raw_mime("text/plain; charset=utf-8")
    assert_equal "text/plain", raw_mime("application/vnd.github+svg")
    assert_equal "text/plain; charset=utf-8", raw_mime("application/vnd.github+json; charset=utf-8")
    assert_equal "text/plain", raw_mime("application/vnd.github+xml")
    assert_equal "image/svg+xml; charset=utf-8", raw_mime("image/svg+xml; charset=utf-8")
    assert_equal "application/zip", raw_mime("application/zip")
    assert_equal "application/zip", raw_mime("application/zip")
    assert_equal "image/png", raw_mime("image/png")
    assert_equal "image/PNG; what=ever", raw_mime("image/PNG; what=ever")
    assert_equal "audio/wav", raw_mime("audio/wav")
    assert_equal "video/mp4", raw_mime("video/mp4")
    assert_equal "application/octet-stream", raw_mime("application/vnd.github+foo")
    assert_equal "application/octet-stream", raw_mime("application/x-shockwave-flash")
    assert_equal "text/plain; charset=utf-8", raw_mime("application/x-shockwave-flash; charset=utf-8", is_text: true)
    assert_equal "video/mp2t", raw_mime("video/mp2t")
    assert_equal "video/vnd.nokia.interleaved-multimedia", raw_mime("video/vnd.nokia.interleaved-multimedia")
    assert_equal "text/plain", raw_mime("video/mp2t", is_text: true)
    assert_equal "text/plain", raw_mime("video/vnd.nokia.interleaved-multimedia", is_text: true)
  end
end

class RawBlobAbstractRepositoryHelpersTest < GitHub::TestCase
  fixtures do
    @user = create :user, login: "skalnik", email: "skalnik@github.com", plan: "small"
    @session = create :user_session, user: @user
  end

  setup do
    @helper = FakeHelper.new
    @helper.extend RawBlob::AbstractRepositoryHelper
    @helper.current_user = @user
    @helper.user_session = @session
    @public_repo = create(:public_repository, owner: @user, name: "simple-repo")
    @private_repo = create(:private_repository, owner: @user, name: "private-repo")
  end

  test "should issue tokens for public repos in private mode" do
    GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests
    GitHub.stubs(:private_mode_enabled?).returns(true)
    @helper.current_repository = @public_repo
    assert !@helper.raw_domain_token(:render, { name: "some/path" }).nil?, "We should get a token for public repos in private mode"
  end

  test "should not issue tokens for public repos normally" do
    @helper.current_repository = @public_repo
    assert @helper.raw_domain_token(:render, { name: "some/path" }).nil?, "No token for public repos normally"
  end
end
