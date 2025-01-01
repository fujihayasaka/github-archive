# typed: true
# frozen_string_literal: true

require "test_helper"

class ServerToServerTokens::DomainTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @integration = create(:integration)
    @authenticatable = make_integration_installation(integration: @integration, target: @user)
  end

  def setup
    @accessor = ServerToServerTokens::Domain.new
  end

  context ".matches_pattern?" do
    test "returns true if matches the old AuthenticationToken pattern" do
      token_value = "v1.#{SecureRandom.hex(20)}"
      assert ServerToServerTokens::Domain.matches_pattern?(token_value)
    end

    test "returns true if matches the AuthenticationToken pattern" do
      _, token_value = AuthenticationToken.create_for(@authenticatable.id, @authenticatable.class.name, {})
      assert ServerToServerTokens::Domain.matches_pattern?(token_value)
    end

    test "returns false if given token is OAuth token" do
      access = create :oauth_access
      token = access.reset_token
      refute ServerToServerTokens::Domain.matches_pattern?(token)
    end
  end

  context ".hash_token" do
    test "returns hashed token" do
      token = "test_token"
      hashed_token = ServerToServerTokens::Domain.hash_token(token)
      assert_equal AuthenticationToken.hash_token(token), hashed_token
    end
  end

  context "#by_unhashed_token" do
    test "returns the token record if found" do
      record, token_value = @authenticatable.generate_token
      result = @accessor.by_unhashed_token(token_value)
      assert_equal record, result
    end

    test "returns nil if token is not found" do
      result = @accessor.by_unhashed_token("invalid_token")
      assert_nil result
    end
  end

  context "#by_hashed_token" do
    test "returns the token record if found" do
      record, token_value = @authenticatable.generate_token
      hashed_token = AuthenticationToken.hash_token(token_value)
      result = @accessor.by_hashed_token(hashed_token)
      assert_equal record, result
    end

    test "returns nil if token is not found" do
      result = @accessor.by_hashed_token("invalid_hashed_token")
      assert_nil result
    end
  end

  context "#by_id" do
    test "returns the token record if found" do
      record, _ = @authenticatable.generate_token
      result = @accessor.by_id(record.id)
      assert_equal record, result
    end

    test "returns nil if token is not found" do
      result = @accessor.by_id(-1)
      assert_nil result
    end
  end

  context "#extend_expires_at" do
    test "extends the expires_at timestamp if valid" do
      record, _ = @authenticatable.generate_token
      new_expires_at = 30.minutes.from_now.iso8601
      result = @accessor.extend_expires_at(record.id, new_expires_at)
      assert result.is_a?(GH::Result::Ok)
      assert_equal new_expires_at, record.reload.expires_at_timestamp.iso8601
    end

    test "returns error if expires_at is too long" do
      record, _ = @authenticatable.generate_token
      new_expires_at = 2.hours.from_now.iso8601
      result = @accessor.extend_expires_at(record.id, new_expires_at)
      assert result.is_a?(GH::Result::Error)
      assert_equal "This access token's expires_at time cannot be extended by more than 60 minutes.", result.message
    end

    test "returns error if expires_at is in the past" do
      record, _ = @authenticatable.generate_token
      new_expires_at = 1.hour.ago.iso8601
      result = @accessor.extend_expires_at(record.id, new_expires_at)
      assert result.is_a?(GH::Result::Error)
      assert_equal "This access token's expires_at time cannot be in the past.", result.message
    end
  end

  context "#destroy" do
    test "destroys the token record if found" do
      record, _ = @authenticatable.generate_token
      result = @accessor.destroy(record.id)
      assert result.is_a?(GH::Result::Ok)
      assert_nil AuthenticationToken.find_by(id: record.id)
    end

    test "returns not found error if token is not found" do
      result = @accessor.destroy(-1)
      assert result.is_a?(GH::Result::Error::NotFound)
    end
  end

  context "#create" do
    test "creates a new token" do
      result = @accessor.create(@authenticatable.id, @authenticatable.class.name, {})
      assert result.is_a?(GH::Result::Ok)
      assert result.value.token_record.persisted?
      assert_match ServerToServerTokens::Domain::TOKEN_PATTERN_GS1, result.value.token_value
    end

    test "requires a real authenticatable" do
      installation = create(:integration_installation)
      installation.delete
      result = @accessor.create(99, "IntegrationInstallation", {})
      assert result.is_a?(GH::Result::Error)
      assert_equal result.message, "Validation failed: Authenticatable must exist"
    end

    test "returns error if invalid type" do
      result = @accessor.create(-1, "InvalidType", {})
      assert result.is_a?(GH::Result::Error)
      assert_equal result.message, "uninitialized constant InvalidType"
    end
  end

  context "#delete_by_authenticatable_id" do
    test "deletes all tokens associated with the authenticatable_id" do
      record, _ = @authenticatable.generate_token
      assert_difference "AuthenticationToken.where(authenticatable_id: @authenticatable.id).count", -1 do
        result = ServerToServerTokens.domain.destroy_by_authenticatable_id(@authenticatable.id)
        assert result.is_a?(GH::Result::Ok)
        assert_equal 1, result.value if result.is_a?(GH::Result::Ok)
      end
    end

    test "handles missing records gracefully" do
      assert_nothing_raised do
        result = ServerToServerTokens.domain.destroy_by_authenticatable_id(-1)
        assert result.is_a?(GH::Result::Ok)
        assert_equal 0, result.value if result.is_a?(GH::Result::Ok)
      end
    end

    test "batches deletion of tokens" do
      3.times { @authenticatable.generate_token }
      AuthenticationToken.stubs(:DESTROY_BATCH_SIZE).returns(2)

      assert_difference "AuthenticationToken.where(authenticatable_id: @authenticatable.id).count", -3 do
        result = ServerToServerTokens.domain.destroy_by_authenticatable_id(@authenticatable.id)
        assert result.is_a?(GH::Result::Ok)
        assert_equal 3, result.value if result.is_a?(GH::Result::Ok)
      end
    end
  end

  context "#by_authenticatable_id" do
    test "returns tokens associated with the authenticatable_id" do
      record, _ = @authenticatable.generate_token
      result = @accessor.by_authenticatable_id(@authenticatable.id)
      assert_equal [record], result
    end

    test "returns empty array if no tokens are found" do
      result = @accessor.by_authenticatable_id(-1)
      assert_equal [], result
    end
  end

  context "#authenticatable_ids_with_active_tokens" do
    test "returns authenticatable_ids with active tokens" do
      record, _ = @authenticatable.generate_token
      result = @accessor.authenticatable_ids_with_active_tokens([@authenticatable.id], @authenticatable.class.name)
      assert_equal [@authenticatable.id], result
    end

    test "returns empty array if no active tokens are found" do
      result = @accessor.authenticatable_ids_with_active_tokens([-1], @authenticatable.class.name)
      assert_equal [], result
    end
  end

  context "#by_unhashed_token_ro" do
    test "returns the token record if found" do
      record, token_value = @authenticatable.generate_token
      result = @accessor.by_unhashed_token_ro(token_value)
      assert_equal record, result
    end

    test "returns nil if token is not found" do
      result = @accessor.by_unhashed_token_ro("invalid_token")
      assert_nil result
    end
  end

  context "#by_hashed_values" do
    test "returns token records if found" do
      record, token_value = @authenticatable.generate_token
      hashed_token = AuthenticationToken.hash_token(token_value)
      result = @accessor.by_hashed_values([hashed_token], 1)
      assert_equal({ hashed_token => record }, result)
    end

    test "returns empty hash if no tokens are found" do
      result = @accessor.by_hashed_values(["invalid_hashed_token"], 1)
      assert_equal({}, result)
    end
  end
end
