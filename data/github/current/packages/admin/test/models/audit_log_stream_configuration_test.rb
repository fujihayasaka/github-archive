# typed: true
# frozen_string_literal: true

require "test_helper"

class AuditLogStreamConfigurationTest < GitHub::TestCase
  include AuditLogSinkTestHelper

  fixtures do
    @actor = create(:user)
    @business = create(:business, owners: [@actor])
  end

  setup do
    setup_keys
  end

  test "token encryption" do
    clear = "this is super secret"

    encrypted = AuditLogStreamConfiguration.public_encrypt_token(clear)
    refute_equal clear, encrypted

    key = RbNaCl::PrivateKey.new(Base64::decode64(@test_private_key))
    box = RbNaCl::Boxes::Sealed.from_private_key(key)
    decrypted = box.decrypt(Base64.decode64(encrypted))
    assert_equal clear, decrypted
  end

  test "validates sink presence" do
    stream = AuditLogStreamConfiguration.new(business: @business, sink: nil)

    refute(stream.valid?, "stream configuration is valid without a sink")
    refute_nil(stream.errors[:sink], "no validation error for sink present")
  end

  test "feature flags disabled" do
    disable_feature_flag(:audit_sso_disclosure)
    stream = AuditLogStreamConfiguration.new(business: @business, sink: AuditLogSplunkSinkConfiguration.new)
    assert_empty stream.feature_flags
  end

  test "feature flags enabled" do
    enable_feature_flag(:audit_sso_disclosure)
    @business.stubs(:source_ip_disclosure_enabled?).returns(true)
    stream = AuditLogStreamConfiguration.new(business: @business, sink: AuditLogSplunkSinkConfiguration.new)
    assert_equal %w[show_actor_ip show_sso_information], stream.feature_flags
  end

  test "stream configuration pagination test", skip_enterprise: true do
    #create 100 businesses to test pagination
    @businesses_for_pagination = []
    (1..10).map do |i|
      name = "businessauditstreamtest#{i}"
      biz = create(:business, name: name, owners: [@actor])
      @businesses_for_pagination << biz
      if i % 2 == 0
        AuditLogStreamConfiguration.new(business: biz, sink: AuditLogSplunkSinkConfiguration.new).save!
      elsif i % 3 == 0
        AuditLogStreamConfiguration.new(business: biz, sink: AuditLogDatadogSinkConfiguration.new).save!
      elsif i % 5 == 0
        AuditLogStreamConfiguration.new(business: biz, sink: AuditLogAzureHubsSinkConfiguration.new).save!
      else
        AuditLogStreamConfiguration.new(business: biz, sink: AuditLogSplunkSinkConfiguration.new).save!
      end
    end


    5.times do |i|
      assert_equal 2, AuditLogStreamConfiguration.streaming_api_confs_with_offset(limit: 2, offset: i * 2).map { |_, v| v.count }.sum
    end

    assert_equal 7, AuditLogStreamConfiguration.streaming_api_confs["splunks"].count
  end

  test "stream configuration skips soft-deleted businesses", skip_enterprise: true do
    enable_feature_flag(:audit_streaming_exclude_softdeleted)

    biz1 = create(:business, name: "biz1", owners: [@actor])
    biz2 = create(:business, name: "biz2", owners: [@actor])

    biz1.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "access_keys",
        encrypted_access_key_id: "SUPER-ENCRYPTED",
        encrypted_secret_key: "EXTRA-ENCRYPTED",
        key_id: "SUPER-SECURE-KEY",
      )
    ).save!

    biz2.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "oidc_auditlog",
        arn_role: "arn:aws:iam::123456789012:role/XYZ",
      )
    ).save!

    biz2.soft_delete!

    assert_equal 1, AuditLogStreamConfiguration.streaming_api_confs["s3_buckets"].count
  end

  test "stream configuration instrument check adds business if check happens before stream is saved", skip_enterprise: true do
    events = subscribe "audit_log_streaming.check"

    biz = create(:business, name: "biz", owners: [@actor])

    stream = AuditLogStreamConfiguration.new(sink: AuditLogSplunkSinkConfiguration.new)

    stream.instrument_check("ok", biz)

    expected_payload = { audit_log_stream_result: "ok", audit_log_stream_sink_details: ":8088", business: biz.slug, business_id: biz.id }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "stream configuration instrument check uses biz it belongs even if business is passed", skip_enterprise: true do
    events = subscribe "audit_log_streaming.check"

    biz = create(:business, name: "biz", owners: [@actor])
    biz2 = create(:business, name: "biz2", owners: [@actor])

    stream = AuditLogStreamConfiguration.new(business: biz, sink: AuditLogSplunkSinkConfiguration.new)

    stream.instrument_check("ok", biz2)

    expected_payload = { audit_log_stream_result: "ok", audit_log_stream_sink_details: ":8088", business: biz.slug, business_id: biz.id }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "stream configuration instrument check adds stream_id when check happens after the stream is saved", skip_enterprise: true do
    events = subscribe "audit_log_streaming.check"

    biz = create(:business, name: "biz", owners: [@actor])

    stream = AuditLogStreamConfiguration.new(business: biz, sink: AuditLogSplunkSinkConfiguration.new)
    stream.save!

    stream.instrument_check("ok", biz)

    expected_payload = { audit_log_stream_result: "ok", audit_log_stream_sink_details: ":8088", audit_log_stream_id: stream.id, business: biz.slug, business_id: biz.id }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "stream configuration instrument destroy adds stream_id, sink type and sink details when stream is destroyed", skip_enterprise: true do
    events = subscribe "audit_log_streaming.destroy"

    biz = create(:business, name: "biz", owners: [@actor])

    stream = AuditLogStreamConfiguration.new(business: biz, sink: AuditLogSplunkSinkConfiguration.new)
    stream.save!
    stream.destroy

    expected_payload = { audit_log_stream_sink: "Splunk", audit_log_stream_sink_details: ":8088", audit_log_stream_id: stream.id, business: biz.slug, business_id: biz.id }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "stream configuration sets api_events enablement status to true if fflag is disabled", skip_enterprise: true do
    biz = create(:business, name: "biz1", owners: [@actor])
    biz.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "access_keys",
        encrypted_access_key_id: "SUPER-ENCRYPTED",
        encrypted_secret_key: "EXTRA-ENCRYPTED",
        key_id: "SUPER-SECURE-KEY",
      )
    ).save!

    disable_feature_flag(:audit_log_streaming_add_api_events_status_in_conf, biz)
    assert AuditLogStreamConfiguration.streaming_api_confs["s3_buckets"].pop[:are_api_events_enabled]
  end

  test "stream configuration sets api_events enablement status to false if fflag is enabled and api events are disabled", skip_enterprise: true do
    biz = create(:business, name: "biz3", owners: [@actor])
    enable_feature_flag(:audit_log_api_events_write, biz)

    biz.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "oidc_auditlog",
        arn_role: "arn:aws:iam::123456789012:role/XYZ",
      )
    ).save!
    enable_feature_flag(:audit_log_streaming_add_api_events_status_in_conf, biz)

    refute AuditLogStreamConfiguration.streaming_api_confs["s3_buckets"].pop[:are_api_events_enabled]
  end

  test "stream configuration sets api_events enablement status to true if fflag is enabled and api events are enabled", skip_enterprise: true do
    biz = create(:business, name: "biz2", owners: [@actor])
    enable_feature_flag(:audit_log_api_events_write, biz)

    biz.enable_api_request_events(actor: @actor)
    biz.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "oidc_auditlog",
        arn_role: "arn:aws:iam::123456789012:role/XYZ",
      )
    ).save!
    enable_feature_flag(:audit_log_streaming_add_api_events_status_in_conf, biz)

    assert AuditLogStreamConfiguration.streaming_api_confs["s3_buckets"].pop[:are_api_events_enabled]
  end

  test "Can't create more than MAX_AUDIT_LOG_STREAMS_ALLOWED stream per business" do
    AuditLogStreamConfiguration::MAX_AUDIT_LOG_STREAMS_ALLOWED.times do
      ddog = AuditLogDatadogSinkConfiguration.create(
        site: "US",
        encrypted_token: "SUPER-ENCRYPTED",
        key_id: "SUPER-SECURE_KEY",
      )

      stream = @business.audit_log_stream_configurations.build(sink: ddog)
      assert stream.save
    end

    ddog = AuditLogDatadogSinkConfiguration.create(
      site: "US",
      encrypted_token: "SUPER-ENCRYPTED",
      key_id: "SUPER-SECURE_KEY",
    )

    stream = @business.audit_log_stream_configurations.build(sink: ddog)
    refute stream.save
  end

  test "idx takes the value of the first free idx available" do
    AuditLogStreamConfiguration::MAX_AUDIT_LOG_STREAMS_ALLOWED.times do
      stream = @business.audit_log_stream_configurations.build(sink: AuditLogDatadogSinkConfiguration.create(
        site: "US",
        encrypted_token: "SUPER-ENCRYPTED",
        key_id: "SUPER-SECURE_KEY",
      ))

      assert stream.save
    end

    stream = @business.audit_log_stream_configurations.find_by_idx(0)
    stream.destroy

    assert_equal 1, @business.audit_log_stream_configurations.first.idx

    stream = @business.audit_log_stream_configurations.build(sink: AuditLogDatadogSinkConfiguration.create(
      site: "US",
      encrypted_token: "SUPER-ENCRYPTED",
      key_id: "SUPER-SECURE_KEY",
    ))
    assert stream.save

    assert_equal 0, stream.idx
  end

  test "stream configuration return idx when fflag is enabled", skip_enterprise: true do
    biz = create(:business, name: "biz2", owners: [@actor])

    stream = biz.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "oidc_auditlog",
        arn_role: "arn:aws:iam::123456789012:role/XYZ",
      )
    )

    stream.idx = 1
    stream.save!
    enable_feature_flag(:audit_log_streaming_multiple_endpoints, biz)

    assert_equal 1, AuditLogStreamConfiguration.streaming_api_confs["s3_buckets"].pop[:idx]
  end

  test "stream configuration is returned when fflag is disabled but idx is equal to 0", skip_enterprise: true do
    biz = create(:business, name: "biz2", owners: [@actor])

    biz.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "oidc_auditlog",
        arn_role: "arn:aws:iam::123456789012:role/XYZ",
      )
    ).save!

    disable_feature_flag(:audit_log_streaming_multiple_endpoints, biz)

    assert_equal 0, AuditLogStreamConfiguration.streaming_api_confs["s3_buckets"].pop[:idx]
  end

  test "stream configuration return old sink_url based if fflag status for multiple streams is disabled", skip_enterprise: true do
    sinks_with_expected_urls = [
      {
        sink: AuditLogS3SinkConfiguration.create(
          bucket: "myBucket",
          authentication_type: "oidc_auditlog",
          arn_role: "arn:aws:iam::123456789012:role/XYZ",
        ),
        expected_url: :show_add_settings_audit_log_stream_enterprise_path
      },
      {
        sink: AuditLogDatadogSinkConfiguration.create(
          site: "US",
          encrypted_token: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_stream_enterprise_path
      },
      {
        sink: AuditLogSplunkSinkConfiguration.create(
          domain: "localhost",
          port: 8088,
          encrypted_token: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_stream_enterprise_path
      },
      {
        sink: AuditLogAzureHubsSinkConfiguration.create(
          name: "myhub",
          encrypted_connstring: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_stream_enterprise_path
      },
      {
        sink: AuditLogAzureBlobSinkConfiguration.create(
          container: "myContainer",
          encrypted_sas_url: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_stream_enterprise_path
      },
      {
        sink: AuditLogGoogleCloudSinkConfiguration.create(
          bucket: "myBucket",
          encrypted_json_credentials: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE-KEY",
        ),
        expected_url: :show_add_settings_audit_log_stream_enterprise_path
      },
      {
        sink: AuditLogHecSinkConfiguration.create(
          domain: "localhost",
          port: 8088,
          encrypted_token: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_stream_enterprise_path
      },
    ]

    sinks_with_expected_urls.each do |sink_with_expected_url|
      biz = create(:business, name: "biz", owners: [@actor])

      disable_feature_flag(:audit_log_streaming_multiple_endpoints, biz)
      stream = biz.audit_log_stream_configurations.build(sink: sink_with_expected_url[:sink])

      stream.idx = 1
      stream.save!

      assert_equal sink_with_expected_url[:expected_url], stream.sink.sink_url_method(biz)
    end
  end

  test "stream configuration return old sink_url based if fflag status for multiple streams is enabled", skip_enterprise: true do
    sinks_with_expected_urls = [
      {
        sink: AuditLogS3SinkConfiguration.create(
          bucket: "myBucket",
          authentication_type: "oidc_auditlog",
          arn_role: "arn:aws:iam::123456789012:role/XYZ",
        ),
        expected_url: :show_add_settings_audit_log_streams_enterprise_path
      },
      {
        sink: AuditLogDatadogSinkConfiguration.create(
          site: "US",
          encrypted_token: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_streams_enterprise_path
      },
      # Splunk is the only one returning the new path
      {
        sink: AuditLogSplunkSinkConfiguration.create(
          domain: "localhost",
          port: 8088,
          encrypted_token: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_streams_enterprise_path
      },
      {
        sink: AuditLogAzureHubsSinkConfiguration.create(
          name: "myhub",
          encrypted_connstring: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_streams_enterprise_path
      },
      {
        sink: AuditLogAzureBlobSinkConfiguration.create(
          container: "myContainer",
          encrypted_sas_url: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_streams_enterprise_path
      },
      {
        sink: AuditLogGoogleCloudSinkConfiguration.create(
          bucket: "myBucket",
          encrypted_json_credentials: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE-KEY",
        ),
        expected_url: :show_add_settings_audit_log_streams_enterprise_path
      },
      {
        sink: AuditLogHecSinkConfiguration.create(
          domain: "localhost",
          port: 8088,
          encrypted_token: "SUPER-ENCRYPTED",
          key_id: "SUPER-SECURE_KEY",
        ),
        expected_url: :show_add_settings_audit_log_streams_enterprise_path
      },
    ]

    sinks_with_expected_urls.each do |sink_with_expected_url|
      biz = create(:business, name: "biz", owners: [@actor])

      enable_feature_flag(:audit_log_streaming_multiple_endpoints, biz)
      stream = biz.audit_log_stream_configurations.build(sink: sink_with_expected_url[:sink])

      stream.idx = 1
      stream.save!

      assert_equal sink_with_expected_url[:expected_url], stream.sink.sink_url_method(biz)
    end
  end

  test "stream configuration skips streams with idx not equal to 0 when multiple streams fflag is disabled", skip_enterprise: true do
    biz1 = create(:business, name: "biz1", owners: [@actor])

    stream1 = biz1.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "access_keys",
        encrypted_access_key_id: "SUPER-ENCRYPTED",
        encrypted_secret_key: "EXTRA-ENCRYPTED",
        key_id: "SUPER-SECURE-KEY",
      )
    )

    stream1.idx = 1
    stream1.save!

    stream2 = biz1.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "oidc_auditlog",
        arn_role: "arn:aws:iam::123456789012:role/XYZ",
      )
    )

    stream2.idx = 0
    stream2.save!

    disable_feature_flag(:audit_log_streaming_multiple_endpoints, biz1)

    assert_equal 1, AuditLogStreamConfiguration.streaming_api_confs["s3_buckets"].count
  end

  test "stream configuration returns two configs given a business with 2 streams", skip_enterprise: true do
    biz1 = create(:business, name: "biz1", owners: [@actor])

    biz1.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "access_keys",
        encrypted_access_key_id: "SUPER-ENCRYPTED",
        encrypted_secret_key: "EXTRA-ENCRYPTED",
        key_id: "SUPER-SECURE-KEY",
      )
    ).save!

    biz1.audit_log_stream_configurations.build(
      sink: AuditLogS3SinkConfiguration.create(
        bucket: "myBucket",
        authentication_type: "oidc_auditlog",
        arn_role: "arn:aws:iam::123456789012:role/XYZ",
      )
    ).save!

    enable_feature_flag(:audit_log_streaming_multiple_endpoints, biz1)

    assert_equal 2, AuditLogStreamConfiguration.streaming_api_confs["s3_buckets"].count
  end

  test "Can't create two streams with same idx and business_id" do
    ddog = AuditLogDatadogSinkConfiguration.create(
      site: "US",
      encrypted_token: "SUPER-ENCRYPTED",
      key_id: "SUPER-SECURE_KEY",
    )

    assert AuditLogStreamConfiguration.new(business: @business, idx: 0, sink: AuditLogSplunkSinkConfiguration.new).save
    stream = AuditLogStreamConfiguration.new(business: @business, idx: 0, sink: AuditLogSplunkSinkConfiguration.new)
    stream.idx = 0
    refute stream.save
  end

  test "Can't create a stream with idx set to 2 or less than 0" do
    ddog = AuditLogDatadogSinkConfiguration.create(
      site: "US",
      encrypted_token: "SUPER-ENCRYPTED",
      key_id: "SUPER-SECURE_KEY",
    )

    assert AuditLogStreamConfiguration.new(business: @business, idx: 0, sink: AuditLogSplunkSinkConfiguration.new).save
    stream = AuditLogStreamConfiguration.new(business: @business, idx: 0, sink: AuditLogSplunkSinkConfiguration.new)
    stream.idx = AuditLogStreamConfiguration::MAX_AUDIT_LOG_STREAMS_ALLOWED
    refute stream.save
    stream.idx = -1
    refute stream.save
  end
end
