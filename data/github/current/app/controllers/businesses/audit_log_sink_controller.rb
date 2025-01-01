# typed: true
# frozen_string_literal: true

# Concrete sink implementations need to inherit from this class
# and implement the `NotImplemented` methods.
#
# Sink routes can the point to the following controller methods:
#
#   - show_add (to either show a configured endpoint or show a form to add an endpoint)
#   - add (to add a new sink using the user-provided params)
#   - update (to update an existing sink using the user-provided params)
#   - check (to verify whether the endpoint can be reached successfully)
class Businesses::AuditLogSinkController < Businesses::BusinessController # rubocop:disable GitHub/ControllersShouldHaveTests
  before_action :business_owner_required,
  :audit_log_streaming_enabled?,
  :audit_log_streaming_multiple_endpoints_disabled?,
  :audit_log_hec_enabled?

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
  only: [:show_add]

  javascript_bundle :"audit-log-streaming"

  # Show a configured sink if the stream is configured,
  # otherwise show an empty form to add it
  def show_add # rubocop:todo GitHub/UseRestfulActions
    stream = current_business.audit_log_stream_configurations.first

    return render_404 if sink_class.nil?

    sink = stream.nil? ? sink_class.new : stream.sink
    render_add_page(stream, sink)
  end

  # Update an existing sink
  def upsert # rubocop:todo GitHub/UseRestfulActions
    stream = current_business.audit_log_stream_configurations.first
    if stream.nil? || stream.sink.nil?
      add
    else
      update(stream)
    end
  end

  # Runs a sink check, i.e: verifies that it can connect to the sink and write to it.
  def check # rubocop:todo GitHub/UseRestfulActions
    stream = current_business.audit_log_stream_configurations.first
    if stream.nil?
      check_new_stream
    else
      check_existing_stream(stream)
    end
  end

  private

  # Add a new sink
  def add
    return render_404 if sink_class.nil?

    sink = set_sink(sink_class.new)

    stream = current_business.audit_log_stream_configurations.build(sink: sink)

    save_stream(stream, sink)
  end

  # Update an existing sink
  def update(stream)
    raise ActiveRecord::RecordNotFound if stream.nil? || stream.sink.nil?
    stream.gh_staff_disabled = false
    sink = set_sink(stream.sink)

    save_stream(stream, sink)
  end

  # Sink name to use in the UI messages, needs to be implemented by child classes
  def sink_name
    helpers.get_sink_name(params[:type])
  end

  # Sink class, needs to be implemented by child classes
  def sink_class
    helpers.get_sink_class(params[:type])
  end

  # Set the given sink attributes using user-provided params, needs to be implemented by child classes
  def set_sink(sink)
    helpers.get_and_set_sink(params, sink)
  end

  # Renders the add page for the sink, needs to be implemented by child classes
  def render_add_page(stream, sink, msg = nil)
    type = params[:type]
    sink_locals = helpers.sink_locals(type, stream, sink, current_business, msg)

    render "businesses/audit_log_#{sink.sink_path.sub('-', '_')}_sink/add", locals: sink_locals # rubocop:disable GitHub/RailsControllerRenderLiteral
  end

  # Checks a new stream
  def check_new_stream
    return render_404 if sink_class.nil?

    sink = set_sink(sink_class.new)
    stream = ::AuditLogStreamConfiguration.new(sink: sink)

    msg = stream.check_sink(current_business, sink)
    render_add_page(stream, sink, msg)
  end

  # Checks an existing stream, i.e: if secrets are not passed, used the stored ones.
  def check_existing_stream(stream)
    return render_404 if sink_class.nil?

    sink = set_sink(sink_class.new)
    stream.sink = sink

    msg = stream.check_sink(current_business, sink)
    render_add_page(stream, sink, msg)
  end

  # Check the stream and save it
  def save_stream(stream, sink)
    msg = stream.check_sink(current_business, sink)

    if msg != "ok"
      flash.now[:error] = "Must have a successful endpoint check to save an audit log stream."
      return show_add
    end

    begin
      saved = stream.save
    rescue ActiveRecord::RecordNotUnique
      flash.now[:error] = "Unable to create a duplicate Audit log stream to #{sink_name}"
      return show_add
    end

    if saved
      redirect_to :show_settings_audit_log_stream_enterprise
      flash[:notice] = "Successfully updated the Audit log stream to #{sink_name}."
    elsif stream.errors.full_messages.to_sentence.include?("Idx has already been taken")
      redirect_to :show_settings_audit_log_stream_enterprise
    else
      flash.now[:error] = "Unable to update the Audit log stream to #{sink_name}: #{stream.errors.full_messages.to_sentence}."
      show_add
    end
  end

  # Whether streaming is enabled
  def audit_log_streaming_enabled?
    return if GitHub.driftwood_streaming_enabled?
    render_404
  end

  def audit_log_streaming_multiple_endpoints_disabled?
    return unless current_business.audit_log_multiple_streaming_endpoint_enabled?
    render_404
  end

  def audit_log_hec_enabled?
    return if params[:type] != "hec"
    return if GitHub.flipper[:audit_log_streaming_hec_option].enabled?(current_business) && !GitHub.enterprise?
    render_404
  end
end
