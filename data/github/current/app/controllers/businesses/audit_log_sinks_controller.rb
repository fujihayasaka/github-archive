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
class Businesses::AuditLogSinksController < Businesses::BusinessController # rubocop:disable GitHub/ControllersShouldHaveTests
  before_action :business_owner_required, :audit_log_streaming_enabled?, :audit_log_streaming_multiple_endpoints_enabled?

  javascript_bundle :"audit-log-streaming"

  # Show a configured sink if the stream is configured,
  # otherwise show an empty form to add it
  def show_add # rubocop:todo GitHub/UseRestfulActions
    id = params.extract_value(:id)
    stream = current_business.audit_log_stream_configurations.find_by(sink_id: id)
    sink = stream.nil? ? sink_class.new : stream.sink

    render_add_page(stream, sink)
  end

  # # Add a new sink
  def add # rubocop:todo GitHub/UseRestfulActions
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

  # Update an existing sink
  def upsert # rubocop:todo GitHub/UseRestfulActions
    id = params.extract_value(:id)
    stream = current_business.audit_log_stream_configurations.find_by(id: id)
    if stream.nil? || stream.sink.nil?
      add
    else
      update(stream)
    end
  end

  # Runs a sink check, i.e: verifies that it can connect to the sink and write to it.
  def check # rubocop:todo GitHub/UseRestfulActions
    id = params.extract_value(:id)
    stream = current_business.audit_log_stream_configurations.find_by(id: id)

    if stream.nil?
      check_new_stream
    else
      check_existing_stream(stream)
    end
  end

  private

  # Sink name to use in the UI messages, needs to be implemented by child classes
  def sink_name
    raise NotImplementedError
  end

  # Sink class, needs to be implemented by child classes
  def sink_class
    raise NotImplementedError
  end

  # Set the given sink attributes using user-provided params, needs to be implemented by child classes
  def set_sink(sink)
    raise NotImplementedError
  end

  # Renders the add page for the sink, needs to be implemented by child classes
  def render_add_page(stream, sink, msg = nil)
    raise NotImplementedError
  end

  # Checks a new stream
  def check_new_stream
    sink = set_sink(sink_class.new)
    stream = ::AuditLogStreamConfiguration.new(sink: sink)

    msg = stream.check_sink(current_business, sink)
    render_add_page(stream, sink, msg)
  end

  # Checks an existing stream, i.e: if secrets are not passed, used the stored ones.
  def check_existing_stream(stream)
    sink = set_sink(sink_class.new)

    msg = stream.check_sink(current_business, sink)
    render_add_page(stream, sink, msg)
  end

  # Check the stream and save it
  def save_stream(stream, sink)
    msg = stream.check_sink(current_business, sink)

    if msg == "ok"
      if stream.save
        redirect_to :settings_audit_log_streams_enterprise
        flash[:notice] = "Successfully updated the Audit log stream to #{sink_name}."
      else
        flash.now[:error] = "Unable to update the Audit log stream to #{sink_name}: #{stream.errors.full_messages.to_sentence}."
        show_add
      end
    else
      flash.now[:error] = "Must have a successful endpoint check to save an audit log stream."
      show_add
    end
  end

  # Whether streaming is enabled
  def audit_log_streaming_enabled?
    return if GitHub.driftwood_streaming_enabled?
    render_404
  end

  def audit_log_streaming_multiple_endpoints_enabled?
    return if current_business.audit_log_multiple_streaming_endpoint_enabled?
    render_404
  end
end
