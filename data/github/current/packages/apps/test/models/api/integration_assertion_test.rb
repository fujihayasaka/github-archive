# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationAssertionTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user  = create(:user)

    @integration = create(:integration, default_permissions: { "contents" => :read })
    key = @integration.generate_key(creator: @user)
    @rsa = key.private_key

    result = @integration.install_on(
      @user,
      repositories: [create(:repository, :minimal, owner: @user)],
      version: @integration.latest_version,
      installer: @user,
      entry_point: :test_case
    )

    assert_predicate result, :success?
    @installation = result.installation
  end

  test "is invalid when given an assertion signed with an unrecognized key" do
    incorrect_rsa = OpenSSL::PKey::RSA.new(2048)

    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(rsa: incorrect_rsa)))

    refute assertion.valid?
    assert_equal :cannot_decode, assertion.error
  end

  test "is invalid if the assertion is not signed at all" do
    assertion = Api::IntegrationAssertion.new(env(jwt: JWT.encode(default_jwt_payload, nil, "none")))

    refute assertion.valid?
    assert_equal :cannot_decode, assertion.error
  end

  test "is invalid if the assertion is not RSA signed" do
    assertion = Api::IntegrationAssertion.new(env(jwt: JWT.encode(default_jwt_payload, "$ecret", "HS256")))

    refute assertion.valid?
    assert_equal :bad_algorithm, assertion.error
  end

  test "is invalid if the assertion doesn't include an 'issued at' claim" do
    payload_without_iat = default_jwt_payload.except(:iat)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload_without_iat)))

    refute assertion.valid?
    assert_equal :iat_blank, assertion.error
  end

  test "is invalid if the assertion's 'issued at' claim is too far in the future" do
    payload = default_jwt_payload.merge(iat: 65.seconds.from_now.to_i)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :iat_invalid, assertion.error
  end

  test "is valid when 'issued at' claim is slightly in the future due to clock skew" do
    payload = default_jwt_payload.merge(iat: 55.seconds.from_now.to_i)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    assert assertion.valid?
    assert_equal @integration, assertion.integration
  end

  test "is invalid if the assertion's 'issued at' claim is malformed" do
    payload = default_jwt_payload.merge(iat: "bogus")
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :iat_invalid, assertion.error
  end

  test "is invalid if the assertion doesn't include an 'expiration time' claim" do
    payload = default_jwt_payload.except(:exp)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :exp_blank, assertion.error
  end

  test "is invalid if the assertion is expired" do
    payload = default_jwt_payload.merge(exp: 65.seconds.ago.to_i)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :exp_invalid, assertion.error
  end

  test "is invalid if the assertion's 'expiration time' claim is too far in the future" do
    payload = default_jwt_payload.merge(exp: 11.minutes.from_now.to_i)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :exp_too_far_out, assertion.error
  end

  test "is invalid if the assertion's 'expiration time' claim is not an integer" do
    payload = default_jwt_payload.merge(exp: { "key" => "val" })
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :exp_invalid, assertion.error
  end

  test "is valid when generated and used in the hour before DST fall back, but everything uses UTC" do
    generate_token_time = DateTime.parse("2018-11-04T01:30:00-07:00") # just before (turns to -8 offset after DST fall back)
    request_time = DateTime.parse("2018-11-04T01:31:00-07:00")
    jwt_payload = { iat: generate_token_time.to_i, #=> 1541325599, removes timezone, thinks this is just 01:59:59
                   exp: (generate_token_time + 10.minutes).to_i,
                   iss: @integration.id }

    Timecop.freeze(request_time) do
      assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: jwt_payload)))
      assert assertion.valid?
    end
  end

  test "is valid when 'expiration time' claim is only slightly expired to account for clock skew" do
    payload = default_jwt_payload.merge(exp: 55.seconds.ago.to_i)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    assert assertion.valid?
    assert_equal @integration, assertion.integration
  end

  test "is invalid if the assertion's 'expiration time' claim is malformed" do
    payload = default_jwt_payload.merge(exp: "bogus")
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :exp_invalid, assertion.error
  end

  test "is invalid if the assertion's 'expiration time' claim isn't numeric" do
    payload = default_jwt_payload.merge(exp: 10.minutes.from_now.to_s)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :exp_invalid, assertion.error
  end

  test "is invalid if the integration has no key" do
    @installation.integration.public_keys.clear
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt))

    refute assertion.valid?
    assert_equal :no_key, assertion.error
  end

  test "is invalid if the assertion doesn't include an 'issuer' claim" do
    payload = default_jwt_payload.except(:iss)
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :iss_blank, assertion.error
  end

  test "is invalid if the 'issuer' assertion is not an integer or number as a string" do
    payload = default_jwt_payload.except(:iss)

    # See https://github.com/github/ecosystem-apps/issues/669#issue-343179485
    payload[:iss] = { type: "Buffer", data: [49, 52, 56, 49, 53] }
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :iss_invalid, assertion.error
  end

  test "is invalid if the 'issuer' assertion is a string as a number but the exp assertion is too far out" do
    payload = default_jwt_payload.except(:iss)

    payload[:iss] = "10"
    payload[:exp] = 12.minutes.from_now.to_i
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :exp_too_far_out, assertion.error
  end

  test "is invalid if the integration is suspended" do
    @integration.suspend(reason: "test", actor: create(:staff_admin_user))

    payload = default_jwt_payload
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
    assert_equal :integration_suspended, assertion.error
  end

  test "is valid if the 'issuer' assertion is a number as a string" do
    payload = default_jwt_payload.except(:iss)
    payload["iss"] = @integration.id.to_s
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    assert assertion.valid?
  end

  test "is valid if the 'issuer' assertion is an integer" do
    payload = default_jwt_payload.except(:iss)
    payload["iss"] = @integration.id.to_i
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    assert assertion.valid?
  end

  test "is valid if the 'issuer' assertion is a client ID and the feature flag is enabled" do
    enable_feature_flag(:jwt_client_id_iss, @integration.owner)

    payload = default_jwt_payload.except(:iss)
    payload["iss"] = @integration.key
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    assert assertion.valid?
  end

  test "is invalid if the 'issuer' assertion is a client ID and the feature flag is disabled" do
    disable_feature_flag(:jwt_client_id_iss)

    payload = default_jwt_payload.except(:iss)
    payload["iss"] = @integration.key
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
  end

  test "is invalid if the 'issuer' assertion is a client ID but the integration no longer exists" do
    enable_feature_flag(:jwt_client_id_iss)

    payload = default_jwt_payload.except(:iss)
    payload["iss"] = @integration.key

    @integration.destroy

    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(payload: payload)))

    refute assertion.valid?
  end

  test "is valid with multiple master keys" do
    # create second key...
    key = @integration.generate_key(creator: @user)
    rsa = key.private_key

    # using new key
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(rsa: rsa)))
    assert assertion.valid?

    # using previous key
    assertion = Api::IntegrationAssertion.new(env(jwt: jwt(rsa: @rsa)))
    assert assertion.valid?
  end

  def env(jwt: nil)
    { "HTTP_AUTHORIZATION" => "Bearer #{jwt}" }
  end

  def jwt(payload: nil, rsa: @rsa)
    payload ||= default_jwt_payload
    JWT.encode(payload, rsa, "RS256")
  end

  def default_jwt_payload
    { iat: Time.now.to_i, exp: 10.minutes.from_now.to_i, iss: @integration.id }
  end
end
