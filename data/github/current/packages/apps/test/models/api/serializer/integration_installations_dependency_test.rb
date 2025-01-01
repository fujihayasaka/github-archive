# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class IntegrationInstallationsTest < Api::SerializerTestCase
  fixtures do
    @integration = create(:integration, default_permissions: { "metadata" => :read })
    user = create(:user)
    repo = create(:repository, :minimal, owner: user)
    make_integration_installation(integration: @integration, repository: repo)
  end

  context "#integration_hash" do
    test "it does not expose sensitive fields by default" do
      output = serialize_hash_method(:integration_hash, @integration)
      refute_predicate output["installations_count"], :present?
    end

    test "it does expose sensitive fields for the current_integration" do
      output = serialize_hash_method(:integration_hash, @integration, current_integration: @integration)
      assert_predicate output["installations_count"], :present?
      assert_equal 1, output["installations_count"]
    end

    test "it does not expose sensitive fields of other integrations" do
      other_integration = create(:integration)
      output = serialize_hash_method(:integration_hash, @integration, current_integration: other_integration)
      refute_predicate output["installations_count"], :present?
    end
  end
end
