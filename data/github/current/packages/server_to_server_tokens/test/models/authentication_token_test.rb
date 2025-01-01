# typed: true
# frozen_string_literal: true

require "test_helper"

class AuthenticationTokenTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @integration = create(:integration)

    @authenticatable = make_integration_installation(integration: @integration, target: @user)
  end

  context ".with_unhashed_token" do
    test "returns nothing if the token is blank" do
      assert_empty AuthenticationToken.with_unhashed_token(nil)
    end

    test "finds the record when the given token value is unhashed" do
      record, token_value = @authenticatable.generate_token
      assert_equal record, AuthenticationToken.with_unhashed_token(token_value).first
    end
  end

  context ".create_for" do
    test "includes the token format version in the token prefix" do
      _, token_value = @authenticatable.generate_token

      assert_match /\Aghs_/, token_value
    end

    test "uses random characters for the token suffix" do
      _, token_value_1 = @authenticatable.generate_token
      _, token_value_2 = @authenticatable.generate_token

      assert_match /[a-zA-Z0-9\-]{36}\z/i, token_value_1
      assert_match /[a-zA-Z0-9\-]{36}\z/i, token_value_2
      refute_equal token_value_1, token_value_2
    end

    test "uses the given authenticatable as the token's owner" do
      token_record, _ = @authenticatable.generate_token

      assert_equal @authenticatable, token_record.authenticatable
    end

    test "generates tokens that match ServerToServerTokens::Domain::TOKEN_PATTERN_GS1" do
      _, token_value = @authenticatable.generate_token

      assert_match ServerToServerTokens::Domain::TOKEN_PATTERN_GS1, token_value
    end

    test "generates tokens with the GS1 pattern for GitHub Connect" do
      enterprise_installation = create :enterprise_installation
      connect_app, connect_app_secret = enterprise_installation.create_github_app

      org = enterprise_installation.owner
      admin = org.admins.first
      result = connect_app.install_on(org, repositories: [], installer: admin, entry_point: :test_case)

      assert_predicate result, :success?
      assert_predicate result.installation.integration, :connect_app?

      _, token_value = result.installation.generate_token
      assert_match ServerToServerTokens::Domain::TOKEN_PATTERN_GS1, token_value
    end

    test "sets the token to expire one hour after creation" do
      Timecop.freeze(Time.parse("2016/01/14 01:13:54Z")) do
        token_record, _ = @authenticatable.generate_token
        assert_equal Time.parse("2016/01/14 02:13:54Z"), token_record.expires_at_timestamp
      end
    end

    test "stores the last 8 characters of the token" do
      token_record, token_value = @authenticatable.generate_token

      assert_match /\A[a-zA-Z0-9]{8}\z/, token_record.token_last_eight
    end
  end

  context ".extend_expires_at" do
    test "updates the record's expires_at_timestamp up to 60 minutes from now" do
      Timecop.freeze do
        record, _ = @authenticatable.generate_token

        result = AuthenticationToken.extend_expires_at(record, 59.minutes.from_now.utc.xmlschema, entry_point: :test_case)
        assert_predicate result, :success?
        assert_equal 59.minutes.from_now.to_i, record.reload.expires_at_timestamp.to_i
      end
    end

    test "does not update the record's expires_at_timestamp for longer than 60 minutes" do
      Timecop.freeze do
        record, _ = @authenticatable.generate_token

        result = AuthenticationToken.extend_expires_at(record, 61.minutes.from_now.utc.xmlschema, entry_point: :test_case)
        assert_predicate result, :failure?
        assert_equal "This access token's expires_at time cannot be extended by more than 60 minutes.", result.message
      end
    end

    test "does not allow the record's expires_at_timestamp to be extended for longer than 24 hours" do
      record, _ =
        Timecop.freeze(25.hours.ago) do
          @authenticatable.generate_token
        end
      record.update!(expires_at_timestamp: 10.minutes.from_now)

      Timecop.freeze do
        result = AuthenticationToken.extend_expires_at(record, 59.minutes.from_now.utc.xmlschema, entry_point: :test_case)
        assert_predicate result, :failure?
        assert_equal  "This access token's expires_at time cannot be extended further.", result.message
      end
    end

    test "does not allow the record's expires_at_timestamp to be set in the past" do
      Timecop.freeze do
        record, _ = @authenticatable.generate_token
        result = AuthenticationToken.extend_expires_at(record, 1.minute.ago.utc.xmlschema, entry_point: :test_case)
        assert_predicate result, :failure?
        assert_equal  "This access token's expires_at time cannot be in the past.", result.message
      end
    end
  end

  context ".active scope" do
    test "returns tokens based on expires_at_timestamp field" do
      token_record, token_value = @authenticatable.generate_token

      Timecop.freeze(DateTime.parse("2019-06-04 10:00:00")) do
        token_record.update_attribute(:expires_at_timestamp, DateTime.parse("2019-06-04 09:30:00"))
        assert_empty AuthenticationToken.active

        token_record.update_attribute(:expires_at_timestamp, DateTime.parse("2019-06-04 10:30:00"))
        assert_equal [token_record], AuthenticationToken.active
      end
    end
  end

  context "validation" do
    test "requires an authenticatable" do
      record = AuthenticationToken.new
      record.valid?

      refute_empty record.errors[:authenticatable]
    end

    test "requires a persisted authenticatable" do
      installation = create(:integration_installation)
      installation.delete

      assert_raises ActiveRecord::RecordInvalid do
        record, _ = AuthenticationToken.create_for(installation.id, installation.class.name, nil)
      end
    end

    test "requires a real authenticatable" do
      installation = create(:integration_installation)
      installation.delete

      assert_raises ActiveRecord::RecordInvalid do
        record, _ = AuthenticationToken.create_for(99, "IntegrationInstallation", nil)
      end
    end

    test "requires a non-empty hashed_value" do
      record = AuthenticationToken.new
      record.valid?

      refute_empty record.errors[:hashed_value]
    end

    test "rejects a hashed_value that exceeds the column length" do
      value = "x" * 500
      record = AuthenticationToken.new(hashed_value: value)
      record.valid?

      refute_empty record.errors[:hashed_value]
    end

    test "works during the hour just before DST" do
      generate_token_time = DateTime.parse("2018-11-04T01:30:00-07:00")
      request_time = DateTime.parse("2018-11-04T01:31:00-07:00")
      Timecop.freeze(generate_token_time) do
        Timecop.travel(generate_token_time) # if this travel is not included, the token's expiration time doesn't get set for an hour later
        token_record, _ = @authenticatable.generate_token

        Timecop.travel(request_time)
        token_record.valid?

        assert_empty token_record.errors[:hashed_value]
      end
    end

    test "can handle DST change boundary correctly" do
      generate_token_time = DateTime.parse("2018-11-04T01:59:59-07:00") # just before
      request_time = DateTime.parse("2018-11-04T01:00:01-08:00") # after DST takes effect
      Timecop.freeze(generate_token_time) do
        Timecop.travel(generate_token_time) # if this travel is not included, the token's expiration time doesn't get set for an hour later
        token_record, _ = @authenticatable.generate_token

        Timecop.travel(request_time)
        assert_predicate token_record, :valid?

        assert_empty token_record.errors[:hashed_value]
      end
    end

    # TODO: this test can be removed once `valid_after` is fully rolled out
    test "it can hold a valid_after timestamp" do
      assert_nil AuthenticationToken.new.valid_after
      valid_after = 1.day.from_now
      token = AuthenticationToken.new(valid_after: valid_after)
      assert_equal valid_after, token.valid_after
    end
  end
end
