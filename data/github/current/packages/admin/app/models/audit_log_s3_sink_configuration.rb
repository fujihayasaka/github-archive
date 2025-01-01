# typed: true
# frozen_string_literal: true

require "monolith-twirp-auditlog-streaming"

class AuditLogS3SinkConfiguration < AuditLogSinkConfiguration

  REGIONS = %w[us-east-1 us-east-2
    us-gov-east-1 us-gov-west-1
    eu-west-1 eu-west-2 eu-west-3
    eu-central-1 eu-central-2 eu-south-1 eu-south-2 eu-north-1
    af-south-1
    ap-east-1 ap-south-1 ap-south-2
    ap-northeast-1 ap-northeast-2 ap-northeast-3
    ap-southeast-1 ap-southeast-2 ap-southeast-3 ap-southeast-4
    ca-central-1 ca-west-1
    il-central-1 me-south-1 me-central-1 sa-east-1].freeze

  SINK_PATH = "s3".freeze
  SINK_TYPE = "Amazon S3".freeze
  STREAMING_API_KEY = "s3_buckets".freeze
  ACCESS_KEYS = "access_keys".freeze
  OIDC_AUDITLOG = "oidc_auditlog".freeze
  OIDC_GITHUB = "oidc_github".freeze

  validates_length_of :bucket, maximum: 1024
  validates_length_of :encrypted_access_key_id, maximum: 1024
  validates_length_of :encrypted_secret_key, maximum: 1024
  validates_length_of :arn_role, maximum: 2048
  validates_length_of :region, maximum: 1024
  validates :region, inclusion: { in: REGIONS, allow_blank: true }

  def event_payload
    updated_attrs_audit = {}
    if saved_change_to_bucket?
      updated_attrs_audit[:new_s3_bucket] = bucket
      updated_attrs_audit[:old_s3_bucket] = bucket_before_last_save if bucket_before_last_save
    end

    if saved_change_to_arn_role?
      updated_attrs_audit[:new_s3_arn_role] = arn_role
      updated_attrs_audit[:old_s3_arn_role] = arn_role_before_last_save if arn_role_before_last_save
    end

    secrets_updated = []
    updated_attrs_audit[:secrets_updated] = secrets_updated.append("Access Key ID") if saved_change_to_encrypted_access_key_id?
    updated_attrs_audit[:secrets_updated] = secrets_updated.append("Secret Key") if saved_change_to_encrypted_secret_key?

    business = T.must(audit_log_stream_configuration).business
    stream_id = T.must(audit_log_stream_configuration).id
    {
      audit_log_stream_sink: sink_type,
      audit_log_stream_id: stream_id,
      business: business,
    }.merge(updated_attrs_audit)
  end

  def check_query(client, business)
    if authentication_type == ACCESS_KEYS
      client.stream_s3_access_keys_check(
        subject_id: business.id,
        bucket: bucket,
        key_id: key_id,
        encrypted_access_key_id: encrypted_access_key_id,
        encrypted_secret_key: encrypted_secret_key,
        region: region
      )
    else
      client.stream_s3_oidc_check(
        subject_id: business.id,
        subject_name: business.slug,
        bucket: bucket,
        arn_role: arn_role,
        region: region
      )
    end
  end

  def sink_url_method(business = nil)
    unless business.audit_log_multiple_streaming_endpoint_enabled?
      return :show_add_settings_audit_log_stream_enterprise_path
    end
    :show_add_settings_audit_log_streams_enterprise_path
  end

  def sink_type
    SINK_TYPE
  end

  def sink_path
    SINK_PATH
  end

  def sink_details
    bucket
  end

  def as_streaming_api_conf
    if authentication_type == ACCESS_KEYS
      {
        bucket: bucket,
        authentication_type: access_keys_auth,
        encrypted_access_key_id: encrypted_access_key_id,
        encrypted_secret_key: encrypted_secret_key,
        region: region,
      }
    else
      {
        bucket: bucket,
        subject_name: T.must(T.must(audit_log_stream_configuration).business).slug,
        authentication_type: oidc_auth,
        arn_role: arn_role,
        region: region,
      }
    end
  end

  def streaming_api_conf_key
    STREAMING_API_KEY
  end

  def access_keys_auth
    MonolithTwirp::Auditlog::Streaming::V1::S3Sink::AuthenticationType::AUTHENTICATION_TYPE_ACCESS_KEYS
  end

  def oidc_auth
    MonolithTwirp::Auditlog::Streaming::V1::S3Sink::AuthenticationType::AUTHENTICATION_TYPE_OIDC_AUDIT_LOG
  end

  def access_keys
    ACCESS_KEYS
  end

  def oidc_auditlog
    OIDC_AUDITLOG
  end

  def oidc_github
    OIDC_GITHUB
  end

  def available_regions
    REGIONS
  end

  def get_input
    bucket
  end
end
