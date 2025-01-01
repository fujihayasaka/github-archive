# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryHydroMessageJobTenantContextTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  class TestHydroMessageJob < HydroMessageJob
    include RepositoryHydroMessageJobTenantContext

    def self.tenants
      @tenants ||= Array.new
    end

    def perform
      self.class.tenants.push(GitHub::CurrentTenant.get&.slug)
    end

    def repository_id
      message.dig(:repository_id) || message.dig(:repository, :id)
    end
  end

  fixtures do
    on_multi_tenant_enterprise do
      @mt_user = create(:emu)
      @mt_business = @mt_user.enterprise_managed_business
      @mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: @mt_business, admin: @mt_user
      @mt_repo = create(:private_repository, owner: @mt_org)
    end
  end

  setup do
    TestHydroMessageJob.tenants.clear
  end

  context "on multi tenant enterprise" do
    test "sets the tenant context to the correct business if repository_id found in message payload" do
      on_multi_tenant_enterprise do
        assert_empty TestHydroMessageJob.tenants
        perform_test_hydro_message_job(message: { repository_id: @mt_repo.id })
        assert_equal [@mt_business.slug], TestHydroMessageJob.tenants
      end
    end

    test "sets the tenant context to the correct business if repository object with id found in message payload" do
      on_multi_tenant_enterprise do
        assert_empty TestHydroMessageJob.tenants
        perform_test_hydro_message_job(message: { repository: {
          id: @mt_repo.id,
        } })
        assert_equal [@mt_business.slug], TestHydroMessageJob.tenants
      end
    end

    test "does not set the tenant context to the correct business if repository id not found" do
      on_multi_tenant_enterprise do
        assert_empty TestHydroMessageJob.tenants
        perform_test_hydro_message_job(message: { repository: {
          id: 0,
        } })
        assert_equal [nil], TestHydroMessageJob.tenants
      end
    end
  end

  private

  def perform_test_hydro_message_job(message:, queue: "test-queue")
    timestamp = Time.now
    TestHydroMessageJob.new(
      protobuf: "some_payload".dup,
      headers: {},
      schema: "hydro.schemas.test.v1.Schema",
      timestamp: timestamp.to_i,
      timestamp_nano: timestamp.to_r,
      message: message,
      queue: "test-queue",
    ).perform_now
  end
end
