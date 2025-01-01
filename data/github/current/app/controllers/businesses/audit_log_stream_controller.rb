# typed: true
# frozen_string_literal: true

class Businesses::AuditLogStreamController < Businesses::BusinessController

  before_action :business_owner_required, :audit_log_streaming_enabled?
  before_action :audit_log_streaming_multiple_endpoints_disabled?, only: [:disable, :remove, :show]
  before_action :redirect_if_multiple_endpoints_enabled, only: [:list]
  before_action :dotcom_required, only: :disable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:list]

  # Redirect to splunk for now until we support more types of services
  def show
    stream = current_business.audit_log_stream_configurations.first
    if stream.nil? || stream.sink_type.nil?
      case params[:sink_type]
      when "azure_blob"
        redirect_to :settings_audit_log_azure_blob_sink_enterprise
      when "azure_hubs"
        redirect_to :settings_audit_log_azure_hubs_sink_enterprise
      when "datadog"
        redirect_to :settings_audit_log_datadog_sink_enterprise
      when "google_cloud"
        redirect_to :settings_audit_log_google_cloud_sink_enterprise
      when "hec"
        redirect_to :settings_audit_log_hec_sink_enterprise
      when "s3"
        redirect_to :settings_audit_log_s3_sink_enterprise
      when "splunk"
        redirect_to :settings_audit_log_splunk_sink_enterprise
      else
        render "businesses/audit_log_stream/show", locals:
          { business: current_business }
      end
    else
      redirect_to :settings_audit_log_stream_list_enterprise
    end
  end

  # Disable a stream (pause/unpause)
  def disable # rubocop:todo GitHub/UseRestfulActions
    stream = current_business.audit_log_stream_configurations.first
    if stream.nil?
      redirect_to :settings_audit_log_stream_enterprise
      return
    end
    enabled = !stream.enabled?
    updated_attrs = { enabled: enabled }.tap do |h|
      h[:paused_at] = enabled ? nil : DateTime.now.utc
      h[:gh_staff_disabled] = false if enabled
    end

    if stream.update(updated_attrs)
      if updated_attrs[:enabled]
        flash[:notice] = "Successfully resumed Audit log streaming to #{sink_type(stream)}"
      else
        flash[:notice] = "Paused Audit log streaming to #{sink_type(stream)}"
      end
      redirect_to :settings_audit_log_stream_list_enterprise
    else
      flash[:error] = "Unable to #{updated_attrs[:enabled] ? "unpause" : "pause"} Audit log stream: #{stream.errors.full_messages.to_sentence}."
      redirect_to :back
    end
  end

  # Delete a stream
  def remove # rubocop:todo GitHub/UseRestfulActions
    stream = current_business.audit_log_stream_configurations.first
    unless stream.nil?
      stream.destroy
      if current_business.save
        flash[:notice] = "Successfully deleted the Audit log stream to #{sink_type(stream)}."
      else
        flash[:error] = "Unable to delete the Audit log stream: #{stream.errors.full_messages.to_sentence}."
      end
    end
    redirect_to :settings_audit_log_stream_enterprise
  end

  def list # rubocop:todo GitHub/UseRestfulActions
    stream = current_business.audit_log_stream_configurations.first
    if stream.nil?
      redirect_to :settings_audit_log_stream_enterprise
      return
    end
    render "businesses/audit_log_stream/list", locals: {
      business: current_business,
      stream: stream,
      sink_url: sink_url(stream),
      sink_type: sink_type(stream),
      sink_details: sink_details(stream),
    }
  end

  private

  def sink_url(stream)
    stream.sink.sink_url(current_business, stream.sink.id)
  end

  def sink_type(stream)
    stream.sink.sink_type
  end

  def sink_details(stream)
    stream.sink.sink_details
  end

  def audit_log_streaming_enabled?
    return if GitHub.driftwood_streaming_enabled?
    render_404
  end

  def redirect_if_multiple_endpoints_enabled
    redirect_to :settings_audit_log_streams_enterprise and return if current_business.audit_log_multiple_streaming_endpoint_enabled?
  end

  def audit_log_streaming_multiple_endpoints_disabled?
    return unless current_business.audit_log_multiple_streaming_endpoint_enabled?
    render_404
  end
end
