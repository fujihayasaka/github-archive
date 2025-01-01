# typed: true
# frozen_string_literal: true

require "test_helper"

class AuditLogWebExportTest < GitHub::TestCase
  include AuditLogExportHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @actor = create(:user)
    @user = create(:user)
    @org = create(:organization)
    @business = create(:business, owners: [@actor])
  end

  setup do
    disable_feature_flag(:audit_log_export_logs)
    disable_feature_flag(:audit_sso_disclosure)
  end

  test "can only create export for user, organization or business" do
    @team = create(:team, organization: @org)

    assert_no_difference "AuditLogWebExport.count" do
      export = AuditLogWebExport.new({
        subject: @team,
        actor: @actor,
        format_type: "json",
        phrase: "abc",
      })

      refute export.valid?
      assert_equal ["is not included in the list"], export.errors[:subject_type]
    end
  end

  test "can only create export json or csv" do
    assert_no_difference "AuditLogWebExport.count" do
      export = AuditLogWebExport.new({
        subject: @org,
        actor: @actor,
        format_type: "xyz",
        phrase: "abc",
      })

      refute export.valid?
      assert_equal ["is not included in the list"], export.errors[:format_type]
    end
  end

  test "cannot create export when other exports are already running" do
    # Max of 3 ongoing exports are allowed

    client = MockExportClient.new(type: WEB, subject: @org)
    client.mock_status

    ids = []
    (1..3).each do |_i|
      export = AuditLogWebExport.create({
        subject: @org,
        actor: @actor,
        format_type: "json",
        phrase: "abc",
        completed: false
      })
      ids << export.export_id
    end

    assert_no_difference "AuditLogWebExport.count" do
      client = MockExportClient.new(type: WEB, subject: @org)
      ids.each { |id| client.mock_status(export_id: id) }

      invalid_export = AuditLogWebExport.new({
        subject: @org,
        actor: @actor,
        format_type: "json",
        phrase: "abc",
      })

      refute invalid_export.valid?
      assert_equal ["can't create another export because the maximum limit of in-progress exports has been reached"], invalid_export.errors[:subject]
    end
  end

  test "can create export for org" do
    assert_difference "AuditLogWebExport.count" do
      export = AuditLogWebExport.create({
        subject: @org,
        actor: @actor,
        format_type: "json",
        phrase: "abc",
      })
      assert export.persisted?
      assert export.export_id?, "expected export id to be generated"
    end
  end

  test "can create export for user" do
    assert_difference "AuditLogWebExport.count" do
      export = AuditLogWebExport.create({
        subject: @user,
        actor: @user,
        format_type: "json",
        phrase: "abc",
      })
      assert export.persisted?
      assert export.export_id?, "expected export id to be generated"
    end
  end

  test "can create export for business" do
    assert_difference "AuditLogWebExport.count" do
      export = AuditLogWebExport.create({
        subject: @business,
        actor: @actor,
        format_type: "json",
        phrase: "abc",
      })
      assert export.persisted?
      assert export.export_id?, "expected export id to be generated"
    end
  end

  test "unique token generated doesn't clash with same export request" do
    client = MockExportClient.new(type: WEB, subject: @org)
    client.mock_status

    export1 = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    export2 = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    refute_equal export1.export_id, export2.export_id
  end

  test "returns export id for parameter" do
    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    assert_equal export.to_param, export.export_id
  end

  test "remote object raises exception when results are not available" do
    client = MockExportClient.new(type: WEB, subject: @org)
    client.mock_status

    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    assert_raises ::AuditLogWebExport::WebExportError do
      export.remote_object
    end
  end

  test "remote object 'get' returns chunks" do
    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })
    client = MockExportClient.new(type: WEB, subject: @org, export_id: export.export_id)
    client.mock_status(status: :STATUS_TYPE_SUCCESSFUL, chunks: 2)
    client.mock_result(export_id: export.export_id, chunk_idx: 0, chunk_data: "1234")
    client.mock_result(export_id: export.export_id, chunk_idx: 1, chunk_data: "5678")
    result = []
    export.remote_object.get do |stuff|
      result << stuff
    end
    assert_equal(%w[1234 5678], result)
  end

  test "remote object 'fetch' returns chunks by index" do
    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })
    client = MockExportClient.new(type: WEB, subject: @org, export_id: export.export_id)
    client.mock_status(status: :STATUS_TYPE_SUCCESSFUL, chunks: 2)
    client.mock_result(export_id: export.export_id, chunk_idx: 1, chunk_data: "5678")
    assert_equal("5678", export.remote_object.fetch(1))
  end

  test "generates instrumentation event for org" do
    events = subscribe "org.audit_log_export"

    client = MockExportClient.new(type: WEB, subject: @org)
    client.mock_start

    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    export.start_export

    expected_payload = {
      org: @org.login,
      org_id: @org.id,
      actor: @actor.login,
      actor_id: @actor.id,
      format_type: "json",
      export_id: export.export_id,
      query_phrase: "abc",
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "get_and_sync_status return STATUS_TYPE_FAILED and updated completed flag when export is expired" do
    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
      completed: "failed",
    })

    travel 1.hour + 1.minute

    assert_equal :STATUS_TYPE_FAILED, export.get_and_sync_status
    assert export.completed, true
  end

  test "get_and_sync_status return STATUS_TYPE_STARTED when export is on going" do
    client = MockExportClient.new(type: WEB, export_id: anything, subject: @org)
    client.mock_status

    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    assert_equal :STATUS_TYPE_STARTED, export.get_and_sync_status
  end

  test "get_and_sync_status return STATUS_TYPE_SUCCESSFUL and update completed flag when export is on done" do
    client = MockExportClient.new(type: WEB, subject: @org)
    client.mock_status(status: :STATUS_TYPE_SUCCESSFUL)

    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
      completed: false
    })

    assert_equal :STATUS_TYPE_SUCCESSFUL, export.get_and_sync_status
    assert export.completed
  end

  test "get_and_sync_status return STATUS_TYPE_FAILED and completed flag when export has failed" do
    client = MockExportClient.new(type: WEB, subject: @org)
    client.mock_status(status: :STATUS_TYPE_FAILED)

    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
      completed: false
    })

    assert_equal :STATUS_TYPE_FAILED, export.get_and_sync_status
    assert export.completed
  end

  test "generates export with feature flag if business has source_ip_disclosure enabled" do
    @business.expects(:source_ip_disclosure_enabled?).returns(true)

    export = AuditLogWebExport.create({
      subject: @business,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    client = MockExportClient.new(type: WEB, export_id: export.export_id, subject: @business, feature_flags: ["show_actor_ip"])
    client.mock_start(disclose_ip_address: true)

    export.start_export
  end

  test "generates export with feature flag if organization has source_ip_disclosure enabled" do
    @org.expects(:source_ip_disclosure_enabled?).returns(true)

    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    client = MockExportClient.new(type: WEB, export_id: export.export_id, subject: @org, feature_flags: ["show_actor_ip"])
    client.mock_start(disclose_ip_address: true)

    export.start_export
  end

  test "generates export with show_sso_information feature flag if business has audit_sso_disclosure enabled" do
    enable_feature_flag(:audit_sso_disclosure, @business)

    export = AuditLogWebExport.create({
      subject: @business,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    client = MockExportClient.new(type: WEB, export_id: export.export_id, subject: @business, feature_flags: ["show_sso_information"])
    client.mock_start

    export.start_export
  end

  test "generates export with show_sso_information feature flag if org has audit_sso_disclosure enabled" do
    enable_feature_flag(:audit_sso_disclosure, @org)

    export = AuditLogWebExport.create({
      subject: @org,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    client = MockExportClient.new(type: WEB, export_id: export.export_id, subject: @org, feature_flags: ["show_sso_information"])
    client.mock_start

    export.start_export
  end

  test "generates export for emu business sets appropriate parameters to driftwood calls" do
    Business.any_instance.stubs(:enterprise_managed_user_enabled?).returns(true)

    export = AuditLogWebExport.create({
      subject: @business,
      actor: @actor,
      format_type: "json",
      phrase: "abc",
    })

    client = MockExportClient.new(type: WEB, export_id: export.export_id, subject: @business)
    client.mock_start

    export.start_export
  end
end
