# typed: true
# frozen_string_literal: true

require "test_helper"

class EnablementChangeServiceTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @org = create(:organization)
    @org_repo = create(:repository, organization: @org)
    @schema = "token_scanning_service.v0.EnablementChange"
  end

  test "publishes a message with user scope for a user owned repo" do
    SecretScanning::Features::Repo::Capabilities.any_instance.stubs(:scannable?).returns(true)
    SecretScanning::Features::Repo::Capabilities.any_instance.stubs(:ghas_secret_scanning?).returns(true)
    SecretScanning::Features::Repo::Capabilities.any_instance.stubs(:results_visible?).returns(true)
    SecretScanning::Features::Repo::Capabilities.any_instance.stubs(:validity_checks?).returns(true)
    SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: @repo)

    assert_hydro_published({
      repository_id: @repo.id,
      owner_id: @repo.owner_id,
      owner_scope: :USER_SCOPE,
      scannable: true,
      ghas_secret_scanning: true,
      results_visible: true,
      validity_checks: true
    }, schema: @schema)
  end

  test "publishes a message with organization scope for an org owned repo" do
    SecretScanning::Features::Repo::Capabilities.any_instance.stubs(:scannable?).returns(true)
    SecretScanning::Features::Repo::Capabilities.any_instance.stubs(:ghas_secret_scanning?).returns(true)
    SecretScanning::Features::Repo::Capabilities.any_instance.stubs(:results_visible?).returns(true)
    SecretScanning::Features::Repo::Capabilities.any_instance.stubs(:validity_checks?).returns(true)
    SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: @org_repo)

    assert_hydro_published({
      repository_id: @org_repo.id,
      owner_id: @org_repo.owner_id,
      owner_scope: :USER_SCOPE,
      scannable: true,
      ghas_secret_scanning: true,
      results_visible: true,
      validity_checks: true
    }, schema: @schema)
  end
end
