# typed: true
# frozen_string_literal: true

require "test_helper"

class DotcomAppOwnerMetadataTest < GitHub::TestCase

  test "can be created" do
    owner = create(:organization)
    local_app = create(:integration)

    owner_metadata = DotcomAppOwnerMetadata.new(
      dotcom_id: owner.id,
      dotcom_type: owner.class.name,
      dotcom_node_id: owner.global_relay_id,
      login: owner.login,
      display_login: owner.display_login,
      url: "https://github.com/#{owner.to_param}",
      avatar_url: owner.primary_avatar_url,
      local_app_id: local_app.id,
      local_app_type: local_app.class.name,
    )

    assert_predicate owner_metadata, :valid?
  end

  test "can have a local app that is an Integration" do
    dotcom_owner = create(:organization)
    local_app = create(:integration)
    owner_metadata = create(:dotcom_app_owner_metadata, dotcom_owner: dotcom_owner, local_app: local_app)

    assert_equal local_app, owner_metadata.local_app
  end

  test "can have a local app that is an OauthApplication" do
    dotcom_owner = create(:organization)
    local_app = create(:oauth_application)
    owner_metadata = create(:dotcom_app_owner_metadata, dotcom_owner: dotcom_owner, local_app: local_app)

    assert_equal local_app, owner_metadata.local_app
  end

  test "can't have a local app that is neither an Integration or OauthApplication" do
    owner = create(:organization)
    local_app = mock
    local_app.stubs(:id).returns(123)

    owner_metadata = DotcomAppOwnerMetadata.new(
      dotcom_id: owner.id,
      dotcom_type: owner.class.name,
      dotcom_node_id: owner.global_relay_id,
      login: owner.login,
      display_login: owner.display_login,
      url: "https://github.com/#{owner.to_param}",
      avatar_url: owner.primary_avatar_url,
      local_app_id: local_app.id,
      local_app_type: local_app.class.name,
    )

    refute_predicate owner_metadata, :valid?
  end

  test "can find owner metadata from a local app" do
    local_app = create(:integration)
    saved_owner_metadata = create(:dotcom_app_owner_metadata, local_app: local_app)

    found_owner_metadata = DotcomAppOwnerMetadata.for_local_app(local_app)
    assert_equal saved_owner_metadata, found_owner_metadata
  end

end
