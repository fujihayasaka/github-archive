# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class AuditLogStreamController < BusinessBaseController
      skip_before_action :dotcom_required
      before_action :audit_log_streaming_stafftools_required

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      def show
        render "stafftools/businesses/audit_log_stream/show", locals: {
          business: this_business,
          streams: streams,
          query_all: search_query_link(this_business.id),
        }
      end

      def check_endpoint # rubocop:todo GitHub/UseRestfulActions
        stream = find_stream

        msg = stream.check_sink(this_business)

        if msg == "ok"
          flash[:notice] = "Check sink was successful."
        else
          flash[:error] = "Check sink for stream with ID: #{stream.id} failed: #{msg}"
        end

        redirect_to :stafftools_audit_log_stream
      end

      def send_disable_warning # rubocop:todo GitHub/UseRestfulActions
        stream = find_stream

        BusinessMailer.audit_log_stream_disabled_warning(this_business, sink_type(stream)).deliver_later
        flash[:notice] = "A warning email has been sent to the business owner of stream with ID: #{stream.id}."
        redirect_to :stafftools_audit_log_stream
      end

      def disable_endpoint # rubocop:todo GitHub/UseRestfulActions
        stream = find_stream

        if stream.update(enabled: false, gh_staff_disabled: true, paused_at: DateTime.now.utc)
          flash[:notice] = "The stream with ID: #{stream.id} has been successfully paused."
          BusinessMailer.audit_log_stream_disabled_stafftools(this_business, sink_type(stream)).deliver_later
        end
        redirect_to :stafftools_audit_log_stream
      end

      private

      def find_stream
        id = params.extract_value(:id)
        stream = this_business.audit_log_stream_configurations.find_by(id: id)
        if stream.nil?
          redirect_to :stafftools_audit_log_stream
          return
        end

        stream
      end

      def streams
        streams = this_business.audit_log_stream_configurations

        stream_locals = []
        streams.each do |stream|
          stream_locals.append(
            {
              stream: stream,
              sink_type: sink_type(stream),
              sink_details: sink_details(stream),
              query_stream: search_query_link(this_business.id, stream.id),
            }
          )
        end

        stream_locals
      end

      def sink_type(stream)
        stream.sink.sink_type
      end

      def sink_details(stream)
        stream.sink.sink_details
      end

      def audit_log_streaming_stafftools_required
        render_404 unless GitHub.driftwood_streaming_stafftools_enabled?
      end

      def search_query_link(business_id, stream_id = nil)
        unless GitHub.driftwood_ade_queries_enabled?
          return "action:audit_log_streaming business_id:#{business_id}"
        end

        query = "webevents | where business_id == #{business_id} and action startswith 'audit_log_streaming'"
        if stream_id != nil
          query << " and data.audit_log_stream_id == #{stream_id}"
        end

        query
      end
    end
  end
end
