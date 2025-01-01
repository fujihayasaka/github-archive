# typed: true
# frozen_string_literal: true

require "test_helper"

class AuditLogSettingsTest < GitHub::TestCase
  if GitHub.single_business_environment?
    setup do
      @business = create(:business)
    end

    context ".retention_months" do
      test "When there is a record in the database" do
        setting = AuditLogSettings.create(business: @business, name: AuditLogSettings::CURATOR_RETENTION_MONTHS_SETTING, value: "3")

        assert_equal setting, AuditLogSettings.retention_months
      end

      test "When there is not a records in the database" do
        setting = AuditLogSettings.retention_months
        refute setting.persisted?
      end
    end

    context ".git_events_enabled?" do
      test "When there is a record in the database" do
        AuditLogSettings.create(business: @business, name: AuditLogSettings::GIT_EVENTS, value: "true")

        assert AuditLogSettings.git_events_enabled?
      end

      test "When there is not a records in the database" do
        refute AuditLogSettings.git_events_enabled?
      end
    end

    test "generates instrumentation event for business" do
      create_events = subscribe "business.audit_log_settings_create"
      events = subscribe "business.audit_log_settings_update"

      setting = AuditLogSettings.create(business: @business, name: AuditLogSettings::CURATOR_RETENTION_MONTHS_SETTING, value: "3")

      expected_payload = {
        name: "curator_retention",
        value: "3",
        business: @business.slug,
        business_id: @business.id,
      }

      assert event = create_events.pop, "a create event was expected"
      assert_equal expected_payload, event.payload

      setting.update(value: "12")

      assert event = events.pop, "an event was expected"
      expected_payload[:value] = "12"
      assert_equal expected_payload, event.payload
    end
  end
end
