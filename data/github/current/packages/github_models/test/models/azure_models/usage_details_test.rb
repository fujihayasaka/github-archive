# typed: true
# frozen_string_literal: true

require "test_helper"

class AzureModelsUsageDetailsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
  end

  test "publishes heliograph.v1.AccountSignalUpdate event if feature is enabled and not GitHub.enterprise?" do
    AzureModels::UsageDetails.create(user_id: @user.id, auths_count: 1)

    message = {
      account_database_id: @user.id,
      account_type: "USER",
      account_global_relay_id: @user.global_relay_id,
      signal: "github_models_usage",
      signal_update_data_json: 1.to_s,
      origin: "azure_models_usage_details",
    }

    with_hydro_publisher(GitHub.hydro_publisher) do
      assert_hydro_published(message, schema: "heliograph.v1.AccountSignalUpdate")
    end
  end unless GitHub.enterprise?
end
