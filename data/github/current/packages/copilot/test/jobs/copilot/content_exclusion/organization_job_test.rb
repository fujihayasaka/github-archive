
# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::ContentExclusion::OrganizationJobTest < GitHub::TestCase
  include CopilotTestHelper
  include JobTestHelper
  include GitHub::LoggerHelper

  test "invalid action" do
    assert_raises ArgumentError do
      Copilot::ContentExclusion::OrganizationJob.perform_now(
        action: :invalid,
        organization_id: 0,
      )
    end
  end

  context "#organization_destroyed" do
    test "does not raise an error" do
      org = create(:organization)
      org.delete

      assert_nothing_raised do
        assert_logged(
          "code.namespace" => "Copilot::ContentExclusion::OrganizationJob",
          "code.function" => "perform",
          "gh.org.id" => org.id,
        ) do
          Copilot::ContentExclusion::OrganizationJob.perform_now(
            action: :organization_destroyed,
            organization_id: org.id,
          )
        end
      end
    end

    test "deletes org-level rules if the org is deleted" do
      rules = create(:copilot_content_exclusion_configuration, :organization)

      org_id = rules.organization_id

      assert_equal Copilot::ContentExclusionConfiguration.count, 1

      assert_logged(
        Body: "Organization destroyed so purged content exclusion configurations",
        "gh.copilot.ignore.deleted.count": 1
      ) do
        Copilot::ContentExclusion::OrganizationJob.perform_now(
          organization_id: org_id,
          action: :organization_destroyed
        )
      end

      assert_equal Copilot::ContentExclusionConfiguration.count, 0
      refute Copilot::ContentExclusionConfiguration.with_organization_ids([org_id]).exists?
    end

    test "deletes repo-level rules if the org is deleted" do
      rules = create(:copilot_content_exclusion_configuration, :repository)

      org_id = rules.organization_id

      assert_equal Copilot::ContentExclusionConfiguration.count, 1

      assert_logged(
        Body: "Organization destroyed so purged content exclusion configurations",
        "gh.copilot.ignore.deleted.count": 1
      ) do
        Copilot::ContentExclusion::OrganizationJob.perform_now(
          organization_id: org_id,
          action: :organization_destroyed
        )
      end

      assert_equal Copilot::ContentExclusionConfiguration.count, 0
      refute Copilot::ContentExclusionConfiguration.with_organization_ids([org_id]).exists?
    end

    test "deletes all rules if the org is deleted" do
      rules = create(:copilot_content_exclusion_configuration, :organization)
      create(:copilot_content_exclusion_configuration, :repository, organization_id: rules.organization_id)

      org_id = rules.organization_id

      assert_equal Copilot::ContentExclusionConfiguration.count, 2

      assert_logged(
        Body: "Organization destroyed so purged content exclusion configurations",
        "gh.copilot.ignore.deleted.count": 2
      ) do
        Copilot::ContentExclusion::OrganizationJob.perform_now(
          organization_id: org_id,
          action: :organization_destroyed
        )
      end

      assert_equal Copilot::ContentExclusionConfiguration.count, 0
      refute Copilot::ContentExclusionConfiguration.with_organization_ids([org_id]).exists?
    end
  end

  test "resolves tenant on a multi-tenant enterprise with business owner" do
    on_multi_tenant_enterprise do
      # Simulate no tenant being set
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get

      business = create(:business)
      organization = create(:organization, business: business)
      organization.delete

      Copilot::ContentExclusion::OrganizationJob.perform_now(
        organization_id: organization.id,
        action: :organization_destroyed
      )

      assert_equal business, GitHub::CurrentTenant.get
    end
  end
end if GitHub.copilot_enabled?
