# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class InsightsEntityBatchHydroMessageJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    class TestHydroMessageJob < InsightsEntityBatchHydroMessageJob
      def self.tenants
        @tenants ||= Array.new
      end

      def perform
        self.class.tenants.push(GitHub::CurrentTenant.get&.slug)
      end

      private

      sig { override.returns(String) }
      def feature_type
        SecurityFeatures::SECRET_SCANNING
      end

      sig { override.returns(String) }
      def target_entity_type
        "secret_scanning_alert"
      end

      sig { override.returns(String) }
      def source_event
        "#{schema}.#{target_entity_type}"
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
      test "sets the tenant context to the correct business" do
        on_multi_tenant_enterprise do
          assert_empty TestHydroMessageJob.tenants
          perform_test_hydro_message_job(message: {
            entity: "secret_scanning_alert",
            entities_updated: [{
              data: secret_scanning_alert_updated_payload(repository_id: @mt_repo.id.to_s, alert_number: "111")
            }],
          })
          assert_equal [@mt_business.slug], TestHydroMessageJob.tenants
        end
      end

      test "does not set the tenant context to the correct business if repository id not found" do
        on_multi_tenant_enterprise do
          assert_empty TestHydroMessageJob.tenants
          perform_test_hydro_message_job(message: {
            entity: "secret_scanning_alert",
            entities_updated: [],
          })
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

    def secret_scanning_alert_updated_payload(repository_id:, alert_number:, **kwargs)
      now = Time.now
      {
        "repository_id" => repository_id,
        "number" => alert_number,
        "created_at" => now.rfc3339(9),
        "updated_at" => now.rfc3339(9),
        "token_type" => "woof",
        "token_type_provider" => "any_provider",
        "slug" => "woof",
        "resolved" => "false",
        "resolution" => "1",
        "resolved_at" => now.rfc3339(9),
        "has_valid_locations" => "true",
        **kwargs
      }.stringify_keys
    end
  end
end
