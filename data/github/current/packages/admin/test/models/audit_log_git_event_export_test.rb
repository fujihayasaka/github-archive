# typed: true
# frozen_string_literal: true

require "test_helper"

class AuditLogGitEventExportTest < GitHub::TestCase
  include AuditLogGitEventExportHelpers
  include AuditLogExportHelpers

  fixtures do
    @actor = create(:user)
    @user = create(:user)
    @org = create(:organization)
    @business = create(:business, owners: [@actor])
  end

  setup do
    disable_feature_flag(:audit_sso_disclosure)
    disable_feature_flag(:audit_log_export_logs)
    @start = DateTime.new(2020, 01, 11, 20, 10, 0)
    @end = DateTime.new(2020, 01, 12, 20, 10, 0)
    @encrypted_phrase = "created:>#{@start.utc.iso8601} created:<#{@end.utc.iso8601}"
  end

  test "remote object raises exception when results are not available" do
    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)
    client.mock_status

    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })

    assert_raises ::AuditLogGitEventExport::ExportError do
      export.remote_object.get
    end
  end

  test "remote object 'get' returns chunks" do
    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)
    client.mock_status(status: :STATUS_TYPE_SUCCESSFUL, chunks: 2)
    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })
    client.mock_result(export_id: export.token, chunk_idx: 0, chunk_data: "1234")
    client.mock_result(export_id: export.token, chunk_idx: 1, chunk_data: "5678")
    result = []
    export.remote_object.get do |stuff|
      result << stuff
    end
    assert_equal(%w[1234 5678], result)
  end

  test "remote object 'fetch' returns chunks by index" do
    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)
    client.mock_status(status: :STATUS_TYPE_SUCCESSFUL, chunks: 2)
    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })
    client.mock_result(export_id: export.token, chunk_idx: 1, chunk_data: "5678")
    assert_equal(:STATUS_TYPE_SUCCESSFUL, export.remote_object.status)
    assert_equal("5678", export.remote_object.fetch(1))
  end

  test "get_and_sync_status return STATUS_TYPE_FAILED and updated completed flag when export is expired" do
    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)

    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })

    travel 1.hour + 1.minute

    assert_equal :STATUS_TYPE_FAILED, export.get_and_sync_status
    assert export.completed
  end

  test "get_and_sync_status return STATUS_TYPE_STARTED when export is on going" do
    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)
    client.mock_status

    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })

    assert_equal :STATUS_TYPE_STARTED, export.get_and_sync_status
    refute export.completed
  end

  test "get_and_sync_status return STATUS_TYPE_SUCCESSFUL and update completed flag when export is on done" do
    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)
    client.mock_status(status: :STATUS_TYPE_SUCCESSFUL)

    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })

    assert_equal :STATUS_TYPE_SUCCESSFUL, export.get_and_sync_status
    assert export.completed
  end

  test "get_and_sync_status return STATUS_TYPE_FAILED and completed flag when export has failed" do
    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)
    client.mock_status(status: :STATUS_TYPE_FAILED)

    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })

    assert_equal :STATUS_TYPE_FAILED, export.get_and_sync_status
    assert export.completed
  end

  test "generates instrumentation event for org" do
    events = subscribe "org.audit_log_git_event_export"

    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)

    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })

    expected_payload = {
      actor: @actor.login,
      actor_id: @actor.id,
      org: @org.login,
      org_id: @org.id,
      start: @start,
      end: @end,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "generates export with feature flag if business has source_ip_disclosure enabled" do
    client = MockExportClient.new(type: GIT, subject: @business, feature_flags: ["show_actor_ip"])
    client.mock_start(encrypted_phrase: @encrypted_phrase)

    @business.expects(:source_ip_disclosure_enabled?).returns(true)

    export = AuditLogGitEventExport.create({
      subject: @business,
      actor: @actor,
      start: @start,
      end: @end,
    })
  end

  test "generates export with feature flag if organization has source_ip_disclosure enabled" do
    client = MockExportClient.new(type: GIT, subject: @org, feature_flags: ["show_actor_ip"])
    client.mock_start(encrypted_phrase: @encrypted_phrase)

    @org.expects(:source_ip_disclosure_enabled?).returns(true)

    export = AuditLogGitEventExport.create({
      subject: @org,
      actor: @actor,
      start: @start,
      end: @end,
    })
  end

  test "generates export with feature flag if business has audit_sso_disclosure enabled" do
    enable_feature_flag(:audit_sso_disclosure, @business)

    client = MockExportClient.new(type: GIT, subject: @business, feature_flags: ["show_sso_information"])
    client.mock_start(encrypted_phrase: @encrypted_phrase)

    export = AuditLogGitEventExport.create({
      subject: @business,
      actor: @actor,
      start: @start,
      end: @end,
    })
    disable_feature_flag(:audit_sso_disclosure)
  end

  test "cannot create export when other exports are already running" do
    client = MockExportClient.new(type: GIT, subject: @org)
    client.mock_start(encrypted_phrase: @encrypted_phrase)
    client.mock_status

    ids = []
    (1..3).each do |_i|
      export = AuditLogGitEventExport.create({
        subject: @org,
        actor: @actor,
        start: @start,
        end: @end,
      })
      ids << export.to_param
    end

    assert_no_difference "AuditLogGitEventExport.count" do
      client = MockExportClient.new(type: GIT, subject: @org)
      ids.each { |id| client.mock_status(export_id: id) }

      invalid_export = AuditLogGitEventExport.new({
        subject: @org,
        actor: @actor,
        start: @start,
        end: @end,
      })

      refute invalid_export.valid?
      assert_equal ["can't create another export because the maximum limit of in-progress exports has been reached"], invalid_export.errors[:subject]
    end
  end
end
