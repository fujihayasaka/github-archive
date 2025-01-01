# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessLicenseConsumptionExport < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @business = create(:business)
    @actor = @business.admins.first
  end

  setup do
    s3_client = Aws::S3::Client.new(stub_responses: true)
    GitHub.stubs(:s3_license_consumption_client).returns(s3_client)
  end

  context "Business::LicenseConsumptionExport" do
    test "can create export for businesses" do
      assert_difference "Business::LicenseConsumptionExport.count" do
        export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)
        assert export.valid?
      end
    end

    test "generates unique token for export request" do
      export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)
      assert export.token?, "expected token to be generated"
    end

    test "format must be json or csv" do
      export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)
      assert export.valid?

      export.format = "json"
      assert export.valid?

      export.format = "csv"
      assert export.valid?

      assert_raises(ArgumentError) do
        export.format = "png"
      end
    end

    test "json content type is determined by format" do
      export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor, format: "json")
      assert_equal "application/json", export.content_type
    end

    test "csv content type is determined by format" do
      export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor, format: "csv")
      assert_equal "text/csv", export.content_type
    end

    test "unique token generated doesn't clash with same export request" do
      export1 = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)
      export2 = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)

      refute_equal export1.token, export2.token
    end

    test "generates instrumentation event for export" do
      events = subscribe "business.business_license_consumption_export"
      Business::LicenseCsvGenerator.any_instance.stubs(:generate).returns("foo,bar")
      export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)
      export.process

      expected_payload = {
        total_entries: 1,
        actor: @actor.login,
        actor_id: @actor.id,
        business: @business.name,
        business_id: @business.id
      }

      assert event = events.pop, "business.business_license_consumption_export event was expected"
      assert_equal expected_payload, event.payload
    end

    if GitHub.hydro_enabled?
      test "publishes github.enterprise_account.v0.EnterpriseReportExport message to Hydro" do
        Business::LicenseCsvGenerator.any_instance.stubs(:generate).returns("foo,bar")
        export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)
        export.process
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          enterprise_size: @business.members.count,
          actor: Hydro::EntitySerializer.user(@actor),
          report_name: Business::LicenseConsumptionExport.name.to_s.underscore,
          notification_sent: false,
        }, schema: "github.enterprise_account.v0.EnterpriseReportExport")
      end
    end

    test "returns token for parameter" do
      export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)
      assert_equal export.to_param, export.token
    end
  end
end
