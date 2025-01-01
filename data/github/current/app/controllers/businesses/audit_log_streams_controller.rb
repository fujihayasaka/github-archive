# typed: true
# frozen_string_literal: true

class Businesses::AuditLogStreamsController < Businesses::BusinessController

  before_action :business_owner_required, :audit_log_streaming_enabled?
  before_action :audit_log_streaming_multiple_endpoints_enabled?, only: [:toggle, :remove]
  before_action :redirect_if_multiple_endpoints_disabled, only: [:show]
  before_action :dotcom_required, only: :toggle

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

  # Redirect to splunk for now until we support more types of services
  def show
    streams = current_business.audit_log_stream_configurations

    stream_locals = []
    streams.each do |stream|
      stream_locals.append(
        {
          stream: stream,
          sink_url: sink_url(stream),
          sink_type: sink_type(stream),
          sink_details: sink_details(stream),
        }
      )
    end

    if params[:sink_type].present?
      case params[:sink_type]
      when "azure_blob"
        redirect_to :settings_audit_log_azure_blob_sinks_show_add_enterprise
      when "azure_hubs"
        redirect_to :settings_audit_log_azure_hubs_sinks_show_add_enterprise
      when "datadog"
        redirect_to :settings_audit_log_datadog_sinks_show_add_enterprise
      when "google_cloud"
        redirect_to :settings_audit_log_google_cloud_sinks_show_add_enterprise
      when "hec"
        redirect_to :settings_audit_log_hec_sinks_show_enterprise
      when "s3"
        redirect_to :settings_audit_log_s3_sinks_show_add_enterprise
      when "splunk"
        redirect_to :settings_audit_log_splunk_sinks_show_add_enterprise
      end
    else
      render "businesses/audit_log_stream/show_multiple_streams", locals: {
        business: current_business,
        streams: stream_locals,
      }
    end
  end

  # Disable a stream (pause/unpause)
  def toggle # rubocop:todo GitHub/UseRestfulActions
    id = params.extract_value(:id)
    stream = current_business.audit_log_stream_configurations.find_by(id: id)
    if stream.nil?
      redirect_to :settings_audit_log_streams_enterprise
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
      redirect_to :settings_audit_log_streams_enterprise
    else
      flash[:error] = "Unable to #{updated_attrs[:enabled] ? "unpause" : "pause"} Audit log stream: #{stream.errors.full_messages.to_sentence}."
      redirect_to :back
    end
  end

  # Delete a stream
  def remove # rubocop:todo GitHub/UseRestfulActions
    id = params.extract_value(:id)
    stream = current_business.audit_log_stream_configurations.find_by(id: id)
    unless stream.nil?
      stream.destroy
      if current_business.save
        flash[:notice] = "Successfully deleted the Audit log stream to #{sink_type(stream)}."
      else
        flash[:error] = "Unable to delete the Audit log stream: #{stream.errors.full_messages.to_sentence}."
      end
    end
    redirect_to :settings_audit_log_streams_enterprise
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

  def redirect_if_multiple_endpoints_disabled
    redirect_to :settings_audit_log_stream_enterprise and return unless current_business.audit_log_multiple_streaming_endpoint_enabled?
  end

  def audit_log_streaming_multiple_endpoints_enabled?
    return if current_business.audit_log_multiple_streaming_endpoint_enabled?
    render_404
  end
end
