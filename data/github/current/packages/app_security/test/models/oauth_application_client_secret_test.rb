# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthApplicationClientSecretTest < GitHub::TestCase
  fixtures do
    @app = create(:oauth_application)
  end

  test "is valid with a creator" do
    secret = @app.client_secrets.build(creator: @app.user)
    assert_predicate secret, :valid?
  end

  test "is recent if accessed" do
    secret = @app.client_secrets.build(creator: @app.user)
    refute_predicate secret, :recent?
    secret.accessed_at = Time.now
    assert_predicate secret, :recent?
  end

  test "generates a secret on create" do
    secret = @app.client_secrets.build(creator: @app.user)
    assert_nil secret.secret_hash
    assert_nil secret.secret_last_eight
    assert secret.save
    refute_nil secret.secret_hash
    refute_nil secret.secret_last_eight
  end

  test "cannot be deleted if it is the only secret" do
    assert_equal 0, @app.client_secrets.count
    secret1 = @app.client_secrets.create(creator: @app.user)
    assert_equal 1, @app.client_secrets.count
    secret = @app.client_secrets.first
    refute secret.destroy
    assert_predicate secret.errors[:base], :any?
  end

  test "can be deleted if there is more than one secret" do
    assert_equal 0, @app.client_secrets.count
    secret1 = @app.client_secrets.create(creator: @app.user)
    secret2 = @app.client_secrets.create(creator: @app.user)
    assert secret1.destroy
    assert_equal 1, @app.client_secrets.count
    assert_equal secret2.id, @app.client_secrets.first.id
  end

  test "limits the number of secrets per app" do
    OauthApplicationClientSecret.stub_const(:MAX_SECRETS, 1) do
      assert_equal 0, @app.client_secrets.count
      secret1 = @app.client_secrets.create(creator: @app.user)
      assert_equal 1, @app.client_secrets.count
      secret2 = @app.client_secrets.create(creator: @app.user)
      refute_predicate secret2, :persisted?
      assert_predicate secret2.errors[:size_limit], :any?
    end
  end

  test "size limit does not affect updates" do
    OauthApplicationClientSecret.stub_const(:MAX_SECRETS, 1) do
      assert_equal 0, @app.client_secrets.count
      secret = @app.client_secrets.create(creator: @app.user)
      assert_equal 1, @app.client_secrets.count
      assert secret.update(accessed_at: Time.now)
    end
  end

  context ".hash_for" do
    test "can handle an Array as invalid input" do
      assert_nothing_raised do
        OauthApplicationClientSecret.hash_for([])
      end
    end
  end
end
