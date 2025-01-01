# typed: true
# frozen_string_literal: true

require "test_helper"

class PermissionsResourceRegistryPermissionsByResourceTest < GitHub::TestCase
  test "returns the permissions requested by an App, grouped by resource type" do
    integration = create(
      :integration,
      default_permissions: {
        "metadata" => :read,
        "contents" => :read,
        "members" => :write,
        "emails" => :read
      }
    )
    assert_equal(
      {
        Repository::Resources => { "metadata" => :read, "contents" => :read },
        Organization::Resources => { "members" => :write },
        User::Resources => { "emails" => :read }
      },
      Permissions::ResourceRegistry.permissions_by_resource(integration)
    )
  end

  test "returns the permissions requested by an installation, grouped by resource type" do
    integration = create(
      :integration,
      default_permissions: {
        "metadata" => :read,
        "contents" => :read,
        "members" => :write,
        "emails" => :read
      }
    )

    org = create(:organization)
    repo = create(:repository, :minimal, owner: org)
    installation = make_integration_installation(integration: integration, repository: repo)

    # The User (emails) permission won't show up here because it's not an
    # installation associated with an OAuth authorization.
    assert_equal(
      {
        Repository::Resources => { "metadata" => :read, "contents" => :read },
        Organization::Resources => { "members" => :write },
      },
      Permissions::ResourceRegistry.permissions_by_resource(installation)
    )
  end
end
