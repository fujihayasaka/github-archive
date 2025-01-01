# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::PermissionsEditorTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration, :with_hook, default_permissions: { "metadata" => :read }, default_events: %w(public))
  end

  def update_integration(integration: @integration, permissions: { "metadata" => :read }, events: %w(public), single_file_name: nil, content_references: {})
    Integration::PermissionsEditor.perform(
      integration: integration,
      permissions_and_events: {
        default_events: events,
        default_permissions: permissions,
        single_file_name: single_file_name,
        default_content_references: content_references,
      },
    )
  end

  context ".perform" do
    context "successful update" do
      test "enqueues the UpgradeIntegrationInstallationVersion job" do
        result = update_integration(permissions: { "metadata" => :read, "contents" => :read })
        assert_predicate result, :success?

        assert_enqueued_with job: UpgradeIntegrationInstallationVersionJob, args: [
          @integration.id, nil, @integration.latest_version.number,
        ]
      end

      test "does not enqueue if the app skips version updates for installations" do
        integration = create_privileged_app_with_capabilities(capabilities: { skip_version_update: true })

        result = update_integration(integration: integration, permissions: { "metadata" => :read, "contents" => :read })
        assert_predicate result, :success?

        assert_no_enqueued_jobs only: UpgradeIntegrationInstallationVersionJob
      end

      test "it does bump #updated_at" do
        updated_at = @integration.updated_at

        Timecop.travel(1.day.from_now) do
          result = update_integration(permissions: { "metadata" => :read, "contents" => :read })
          assert_predicate result, :success?
        end

        refute_equal updated_at, @integration.reload.updated_at
      end
    end

    context "failed update" do
      test "does not enqueue the UpgradeIntegrationInstallationVersionJob" do
        result = update_integration(events: %w(public push))
        assert_predicate result, :failed?

        assert_no_enqueued_jobs only: UpgradeIntegrationInstallationVersionJob
      end

      test "restricts errors from integration single file" do
        result = update_integration(permissions: { "single_file" => :read }, single_file_name: "t" * 256)
        assert_predicate result, :failed?
        assert_includes result.error, "Single file name"
        refute_includes result.error, "Single files path"
      end

      test "returns the errored integration" do
        result = update_integration(events: %w(public push))

        assert_predicate result, :failed?
        refute_predicate result.integration, :valid?
      end
    end
  end
end
