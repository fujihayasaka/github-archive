# typed: strict
# frozen_string_literal: true

class AuditLogMicrosoftPurviewSinkConfiguration < AuditLogSinkConfiguration
  attribute :tenant_id, :uuid_type

  SINK_PATH = T.let("microsoft-purview".freeze, String)
  SINK_TYPE = T.let("Microsoft Purview".freeze, String)
  STREAMING_API_KEY = T.let("purviews".freeze, String)
  TENANT_ID_FORMAT = T.let(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.freeze, Regexp)

  validates :tenant_id, presence: true, format: { with: TENANT_ID_FORMAT, message: "must be a valid UUID" }

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    updated_attrs_audit = {}

    if saved_change_to_tenant_id?
      updated_attrs_audit[:new_purview_tenant_id] = tenant_id
      updated_attrs_audit[:old_purview_tenant_id] = tenant_id_before_last_save if tenant_id_before_last_save
    end

    business = T.must(audit_log_stream_configuration).business
    stream_id = T.must(audit_log_stream_configuration).id
    {
      audit_log_stream_sink: sink_type,
      audit_log_stream_id: stream_id,
      business: business,
    }.merge(updated_attrs_audit)
  end

  # Purview authentication is handled via Azure Workload Identity (FIC).
  # The check passes the tenant_id so driftwood can verify the configuration.
  sig { override.params(client: T.untyped, business: T.untyped).returns(T.untyped) }
  def check_query(client, business)
    client.stream_purview_check(
      subject_id: business.id,
      subject_type: :SUBJECT_TYPE_BUSINESS,
      entra_tenant_id: tenant_id,
    )
  end

  # Purview uses a dedicated authorize route that only accepts (business), so the
  # base-class sink_url (which calls sink_url_method then forwards all three args)
  # cannot be used. sink_url is overridden directly below instead.
  sig { override.params(business: T.untyped).returns(Symbol) }
  def sink_url_method(business = nil)
    raise NotImplementedError, "Purview uses a dedicated authorize route; call sink_url directly"
  end

  sig { override.params(business: T.untyped, type: T.untyped, stream_id: T.untyped).returns(String) }
  def sink_url(business, type = nil, stream_id = nil)
    if stream_id
      UrlHelpers.microsoft_purview_show_settings_audit_log_streams_enterprise_path(business, stream_id)
    else
      UrlHelpers.microsoft_purview_authorize_settings_audit_log_streams_enterprise_path(business)
    end
  end

  sig { override.returns(T::Boolean) }
  def view_only_edit?
    true
  end

  sig { override.returns(String) }
  def sink_type
    SINK_TYPE
  end

  sig { override.returns(String) }
  def sink_path
    SINK_PATH
  end

  sig { override.returns(T.untyped) }
  def sink_details
    tenant_id
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def as_streaming_api_conf
    { entra_tenant_id: tenant_id }
  end

  sig { override.returns(String) }
  def streaming_api_conf_key
    STREAMING_API_KEY
  end

  sig { override.returns(T.untyped) }
  def get_input
    tenant_id
  end
end
