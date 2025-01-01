# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"
require "github-kredz"

class ActionsSecretsSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    make_trusted_oauth_apps_owner

    @repository   = create :repository
    @actions_app  = create :launch_integration

    @installation = make_integration_installation integration: @actions_app, target: @repository.owner, permissions: { "actions" => :write }

    @timestamp = Google::Protobuf::Timestamp.new(seconds: 123456)
  end

  context "actions_secret_hash" do
    test "payload is valid" do
      secret = GitHub::Launch::Services::Credz::Credential.new(name: "A_TOKEN", created_at: @timestamp)
      output = actions_secret(secret)

      assert_equal output["created_at"], "1970-01-02T10:17:36Z"
      assert_equal output["updated_at"], "1970-01-02T10:17:36Z"
    end

    test "sets updated_at even if it's nil" do
      secret = GitHub::Launch::Services::Credz::Credential.new(name: "A_TOKEN", created_at: @timestamp)
      output = actions_secret(secret)

      assert output["updated_at"]
    end
  end

  context "#actions_secrets_hash" do
    test "payload is valid" do
      secret = GitHub::Launch::Services::Credz::Credential.new(name: "A_TOKEN", created_at: @timestamp)
      another_secret = GitHub::Launch::Services::Credz::Credential.new(name: "ANOTHER_TOKEN", created_at: @timestamp)

      app = Api::App.new!

      secrets = app.paginate_rel([secret, another_secret], { per_page: 100, page: 1 })
      output = actions_secrets({ secrets: secrets, total_count: secrets.total_entries })

    end
  end
end
