# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallationRequestTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @integration = create(:integration, public: true, owner: @org, default_permissions: { "metadata" => :read })
    @org.add_member(@user)
    @repository = create(:public_repository, :minimal, owner: @org)

    @request = IntegrationInstallationRequest.create!(
      requester: @user,
      integration: @integration,
      target: @org,
      repositories: [@repository],
    )
  end

  context "validation" do
    test "requires an issuing requester" do
      request = IntegrationInstallationRequest.new
      request.valid?

      refute_predicate request.errors[:requester], :blank?
    end

    test "requires a requested integration" do
      request = IntegrationInstallationRequest.new
      request.valid?

      refute_predicate request.errors[:integration], :blank?
    end

    test "requires a target" do
      request = IntegrationInstallationRequest.new
      request.valid?

      refute_predicate request.errors[:target], :blank?
    end

    test "requires target to be an organization" do
      request = IntegrationInstallationRequest.new(target: @user)
      request.valid?

      refute_predicate request.errors[:target], :blank?
      assert_match %r{Must be an Organization}i, request.errors[:target].first
    end

    test "valid if no repositories are set" do
      @request.repository_requests.clear
      assert_empty @request.repositories
      assert_predicate @request, :valid?
    end

    test "valid if all attributes are set" do
      assert_predicate @request, :valid?
    end
  end

  context "persistence" do
    test "can be persisted with zero repositories" do
      @request.repository_requests.clear
      assert_equal 0, @request.repositories.length
    end

    test "can be persisted with one repository" do
      assert_equal 1, @request.repositories.length
    end
  end

  context "repositories" do
    test "zero repositories means all current and future repositories if integration has repo permissions" do
      @request.repository_requests.clear

      assert @integration.repository_installation_required?(@request.target)

      assert_predicate @request, :request_all_repositories?
      refute_predicate @request, :request_some_repositories?
      refute_predicate @request, :request_no_repositories?
    end

    test "zero repositories NO repositories if integration does not have repository permissions" do
      @integration = create(:integration, public: true, owner: @org, default_permissions: {})
      refute @integration.repository_installation_required?(@org)

      @request = IntegrationInstallationRequest.create!(
          requester: @user,
          integration: @integration,
          target: @org,
          repositories: [],
      )
      refute_predicate @request, :request_all_repositories?
      refute_predicate @request, :request_some_repositories?
      assert_predicate @request, :request_no_repositories?
    end

    test "one repository means it is a request for a subset of the target's repositories" do
      assert @request.integration.repository_installation_required?(@request.target)

      refute_predicate @request, :request_all_repositories?
      assert_predicate @request, :request_some_repositories?
      refute_predicate @request, :request_no_repositories?
    end
  end

  context "#close" do
    test "destroys and returns true when successfully closed" do
      assert @request.close(reason: :canceled, actor: @user), "failed to close request"
      assert_predicate @request, :destroyed?
    end
  end

  context "audit" do
    test "instruments request creation" do
      events = subscribe "integration_installation_request.create"
      @request = IntegrationInstallationRequest.create!(
          requester: @user,
          integration: @integration,
          target: @org,
          repositories: [@repository],
      )

      expected_payload = {
        installation_request_id: @request.id,
        integration: @integration.name,
        integration_id: @integration.id,
        repository_ids: @request.repositories.ids,
        requester: @user.login,
        requester_id: @user.id,
        target: @org.display_login,
        target_id: @org.id,
        org: @org.name,
        org_id: @org.id,
      }
      assert event = events.pop, "a integration_installation_request.create event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments request cancellation" do
      events = subscribe "integration_installation_request.close"
      expected_payload = {
        reason: :canceled,
        actor: @request.requester.login,
        actor_id: @request.requester_id,
        installation_request_id: @request.id,
        integration: @request.integration.name,
        integration_id: @request.integration.id,
        repository_ids: @request.repositories.ids,
        requester: @request.requester.login,
        requester_id: @request.requester.id,
        target: @request.target.name,
        target_id: @request.target.id,
        org: @request.target.name,
        org_id: @request.target.id,
      }
      assert @request.close(reason: :canceled, actor: @request.requester), @request.errors

      assert event = events.pop, "a integration_installation_request.close event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments request rejection" do
      events = subscribe "integration_installation_request.close"
      admin = @org.admins.first

      expected_payload = {
        reason: :rejected,
        actor: admin.login,
        actor_id: admin.id,
        installation_request_id: @request.id,
        integration: @request.integration.name,
        integration_id: @request.integration.id,
        repository_ids: @request.repositories.ids,
        requester: @request.requester.login,
        requester_id: @request.requester.id,
        target: @request.target.name,
        target_id: @request.target.id,
        org: @request.target.name,
        org_id: @request.target.id,
      }
      assert @request.close(reason: :rejected, actor: admin), @request.errors

      assert event = events.pop, "a integration_installation_request.close event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments request approval" do
      events = subscribe "integration_installation_request.close"
      admin = @org.admins.first

      expected_payload = {
        reason:                  :approved,
        installation_request_id: @request.id,
        integration:             @request.integration.name,
        integration_id:          @request.integration.id,
        repository_ids:          @request.repositories.ids,
        requester:               @request.requester.login,
        requester_id:            @request.requester.id,
        target:                  @request.target.name,
        target_id:               @request.target.id,
        actor:                   admin.login,
        actor_id:                admin.id,
        org:                     @request.target.name,
        org_id:                  @request.target.id,
      }
      assert @request.close(reason: :approved, actor: admin), @request.errors

      assert event = events.pop, "a integration_installation_request.close event was expected"
      assert_equal expected_payload, event.payload
    end
  end
end
