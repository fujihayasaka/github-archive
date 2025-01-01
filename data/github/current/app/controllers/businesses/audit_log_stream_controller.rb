# typed: true
# frozen_string_literal: true

class Businesses::AuditLogStreamController < Businesses::BusinessController

  before_action :business_owner_required, :audit_log_streaming_enabled?
  before_action :audit_log_streaming_multiple_endpoints_disabled?, only: [:toggle, :remove]
  before_action :redirect_if_multiple_endpoints_enabled, only: [:list, :show]
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
    if params[:sink_type].present?
      return redirect_to UrlHelpers.show_add_settings_audit_log_stream_enterprise_path(slug: current_business.slug, type: params[:sink_type])
    end

    stream = current_business.audit_log_stream_configurations.first
    unless stream.nil? || stream.sink_type.nil?
      return list
    end

    render "businesses/audit_log_stream/show", locals:
      { business: current_business }
  end

  # Disable a stream (pause/unpause)
  def toggle # rubocop:todo GitHub/UseRestfulActions
    stream = current_business.audit_log_stream_configurations.first
    if stream.nil?
      redirect_to :show_settings_audit_log_stream_enterprise
      return
    end
    enabled = !stream.enabled?
    updated_attrs = { enabled: enabled }.tap do |h|
      h[:paused_at] = enabled ? nil : DateTime.now.utc
      h[:gh_staff_disabled] = false if enabled
    end

    if stream.update(updated_attrs)
      if updated_attrs[:enabled]
        flash[:notice] = "Successfully resumed Audit log streaming to #{helpers.sink_type(stream)}"
      else
        flash[:notice] = "Paused Audit log streaming to #{helpers.sink_type(stream)}"
      end
      redirect_to :show_settings_audit_log_stream_enterprise
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
        flash[:notice] = "Successfully deleted the Audit log stream to #{helpers.sink_type(stream)}."
      else
        flash[:error] = "Unable to delete the Audit log stream: #{stream.errors.full_messages.to_sentence}."
      end
    end
    redirect_to :show_settings_audit_log_stream_enterprise
  end

  private

  def list
    stream = current_business.audit_log_stream_configurations.first
    if stream.nil?
      redirect_to :show_settings_audit_log_stream_enterprise
      return
    end
    render "businesses/audit_log_stream/list", locals: {
      business: current_business,
      stream: stream,
      sink_url: helpers.sink_url(current_business, stream, helpers.sink_path(stream).downcase),
      sink_type: helpers.sink_type(stream),
      sink_details: helpers.sink_details(stream),
    }
  end

  def audit_log_streaming_enabled?
    return if GitHub.driftwood_streaming_enabled?
    render_404
  end

  def redirect_if_multiple_endpoints_enabled
    redirect_to :show_settings_audit_log_streams_enterprise and return if current_business.audit_log_multiple_streaming_endpoint_enabled?
  end

  def audit_log_streaming_multiple_endpoints_disabled?
    return unless current_business.audit_log_multiple_streaming_endpoint_enabled?
    render_404
  end
end
