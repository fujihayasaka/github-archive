# typed: true
# frozen_string_literal: true

require "test_helper"

class ProximaServiceTokenTest < GitHub::TestCase
  fixtures do
    @stamp = "staff-wus2-01"
    @secret_key = "hunter2"

    # seed HMAC key so config properly picks it up
    ENV["PROXIMA_SERVICE_IDENTITY_SECRET_KEY_#{@stamp.underscore.upcase}"] = @secret_key

    @identity = ProximaServiceIdentity.create!(
      tenant_shortcode: "fe088e40",
      service_name: "actions",
      rate_limit: 9001,
    )
  end

  context ".generate" do
    test "token is signed with the appropriate payload" do
      now = Time.now.utc

      Timecop.freeze(now) do
        token = ProximaServiceToken.generate(
          stamp: "staff-wus2-01",
          tenant_shortcode: "test-tenant",
          service_name: "actions",
        )
        assert token

        verified, _ = JWT.decode(token, "hunter2", true)
        assert verified

        # validate standard claims
        assert_equal "github.com", verified["iss"]
        assert_equal "api.github.com", verified["aud"]
        assert_equal now.to_i, verified["iat"]
        assert_equal (now + 1.hour).to_i, verified["exp"]

        # validate custom claims
        assert_equal @stamp, verified["stamp"]
        assert_equal "test-tenant", verified["tenant_shortcode"]
        assert_equal "actions", verified["service_name"]
      end
    end

    context "validations" do
      test "tenant_shortcode is required to be nonempty" do
        assert_raises_with_message(ArgumentError, "bad tenant") do
          token = ProximaServiceToken.generate(
            stamp: "staff-wus2-01",
            tenant_shortcode: "",
            service_name: "actions",
          )
        end
      end

      test "stamp must be recognized" do
        GitHub::Config::Proxima::ALL_STAMPS.each do |stamp|
          assert ProximaServiceToken.generate(
            stamp: stamp,
            tenant_shortcode: "test-tenant",
            service_name: "actions",
            secret: "#{stamp}-secret-key",
          )
        end

        assert_raises_with_message(ArgumentError, "invalid stamp") do
          token = ProximaServiceToken.generate(
            stamp: "the-literal-moon",
            tenant_shortcode: "test-tenant",
            service_name: "actions",
            secret: "moon-secret-key"
          )
        end
      end

      test "service_name must be registered" do
        ProximaServiceIdentity::REGISTERED_SERVICES.each do |service_name|
          assert ProximaServiceToken.generate(
            stamp: "staff-wus2-01",
            tenant_shortcode: "test-tenant",
            service_name: service_name,
          )
        end

        assert_raises_with_message(ArgumentError, "service not registered") do
          token = ProximaServiceToken.generate(
            stamp: "staff-wus2-01",
            tenant_shortcode: "test-tenant",
            service_name: "giant-space-laser",
          )
        end
      end

      test "duration must be valid" do
        # valid stamps are accepted
        [1.minute, ProximaServiceToken::DEFAULT_DURATION, ProximaServiceToken::MAX_DURATION].each do |duration|
          assert ProximaServiceToken.generate(
            stamp: "staff-wus2-01",
            tenant_shortcode: "test-tenant",
            service_name: "actions",
            duration: duration,
          )
        end

        assert_raises_with_message(ArgumentError, "duration must be positive") do
          token = ProximaServiceToken.generate(
            stamp: "staff-wus2-01",
            tenant_shortcode: "test-tenant",
            service_name: "actions",
            duration: -1.minute,
          )
        end

        assert_raises_with_message(ArgumentError, "duration too long") do
          token = ProximaServiceToken.generate(
            stamp: "staff-wus2-01",
            tenant_shortcode: "test-tenant",
            service_name: "actions",
            duration: 6.hours + 1.minute,
          )
        end
      end
    end
  end

  context ".verify" do
    test "extracts claims from tokens with valid signatures" do
      token = generate_token
      pst = ProximaServiceToken.verify(token)
      assert pst

      assert pst.valid?
      assert pst.stamp, @stamp

      # permits tokens with no identity in MySQL
      assert pst.identity
      assert_equal "test-tenant", pst.identity&.tenant_shortcode
      assert_equal "actions", pst.identity&.service_name

      # temporary identity cannot be persisted to MySQL
      refute pst.identity&.id
      assert pst.identity&.readonly?
      assert_raises ActiveRecord::ReadOnlyRecord do
        T.must(pst.identity).save
      end
    end

    test "returns durable identity if present" do
      token = generate_token(tenant_shortcode: @identity.tenant_shortcode)
      pst = ProximaServiceToken.verify(token)
      assert pst

      assert pst.valid?
      assert pst.stamp, @stamp

      # identity record exists and can be updated
      assert_equal @identity, pst.identity
      T.must(pst.identity).tenant_shortcode = "other-tenant"
      T.must(pst.identity).save
    end

    test "rejects token signed with invalid signature" do
      invalid_token = generate_token(secret: "ch1pmunk")

      pst = ProximaServiceToken.verify(invalid_token)
      assert pst.failed?

      assert_equal pst.reason, :bad_token
      refute pst.identity
    end

    test "rejects token signed with wrong secret" do
      token = generate_token
      header, payload, signature = token.split(".")

      # this is fun.  change the case of all letters in signature. if they're still the same (i.e. all digits), change the last character to non-digit.
      invalid_signature = signature.swapcase
      invalid_signature[-1] = "a" if signature == invalid_signature
      invalid_token = [header, payload, invalid_signature].join(".")

      pst = ProximaServiceToken.verify(invalid_token)
      assert pst.failed?

      assert_equal pst.reason, :bad_token
      refute pst.identity
    end

    test "rejects token if stamp is valid but no signing key found" do
      # use a stamp from GitHub::Config::Proxima::ALL_STAMPS that wasn't seeded in fixtures
      token = generate_token(stamp: "prod-weu-01")
      error = assert_raises(RuntimeError) { ProximaServiceToken.verify(token) }
      assert_equal "no signing key found for prod-weu-01", error.message
    end

    test "rejects token if stamp is valid but signing key has no value" do
      ENV["PROXIMA_SERVICE_IDENTITY_SECRET_KEY_PROD_WEU_01"] = ""

      token = generate_token(stamp: "prod-weu-01")
      error = assert_raises(RuntimeError) { ProximaServiceToken.verify(token) }
      assert_equal "no signing key found for prod-weu-01", error.message

      ENV.delete("PROXIMA_SERVICE_IDENTITY_SECRET_KEY_PROD_WEU_01")
    end

    context "validations" do
      test "ensures presence of stamp" do
        token = generate_token(stamp: "")
        pst = ProximaServiceToken.verify(token)
        assert pst.failed?

        assert_equal pst.reason, :missing_stamp
        refute pst.identity
      end

      test "ensures valid stamp" do
        token = generate_token(stamp: "the-literal-moon")
        pst = ProximaServiceToken.verify(token)
        assert pst.failed?

        assert_equal pst.reason, :bad_stamp
        refute pst.identity
      end

      test "validates audience" do
        token = generate_token(aud: "gist.github.com")
        pst = ProximaServiceToken.verify(token)
        assert pst.failed?

        assert_equal pst.reason, :bad_token
        refute pst.identity
      end

      test "validity window must not exceed MAX_DURATION" do
        token = generate_token(duration: ProximaServiceToken::MAX_DURATION + 1.minute)
        pst = ProximaServiceToken.verify(token)
        assert pst.failed?

        assert_equal pst.reason, :token_duration_too_long
        refute pst.identity
      end
    end
  end

  # enables bypassing of validations in .generate
  def generate_token(
    iss: "github.com",
    aud: "api.github.com",
    stamp: @stamp,
    tenant_shortcode: "test-tenant",
    service_name: "actions",
    duration: ProximaServiceToken::DEFAULT_DURATION,
    secret: @secret_key
  )
    payload = {
      # standard claims
      iss: iss,
      aud: aud,
      exp: duration.from_now.utc.to_i,
      iat: Time.now.utc.to_i,
      # custom claims
      stamp: stamp,
      tenant_shortcode: tenant_shortcode,
      service_name: service_name,
    }.compact

    JWT.encode(payload, secret, "HS256", { typ: "JWT" })
  end
end
