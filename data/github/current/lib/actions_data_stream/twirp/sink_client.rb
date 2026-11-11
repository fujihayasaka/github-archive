# typed: true
# frozen_string_literal: true

module ActionsDataStream
  module Twirp
    class SinkClient < BaseClient

      def list_sinks(owner_type:, owner_id:)
        rpc(:ListSinks, owner_type: owner_type, owner_id: owner_id)
      end

      def get_sink(owner_type:, owner_id:, id:)
        rpc(:GetSink, owner_type: owner_type, owner_id: owner_id, id: id)
      end

      def get_sink_by_name(owner_type:, owner_id:, name:)
        rpc(:GetSinkByName, owner_type: owner_type, owner_id: owner_id, name: name)
      end

      def create_sink(owner_type:, owner_id:, name:, sink_type:, config:)
        rpc(:CreateSink, owner_type: owner_type, owner_id: owner_id, name: name, sink_type: sink_type, config: config)
      end

      def update_sink(owner_type:, owner_id:, id:, name: nil, status: nil, config: nil)
        params = { owner_type: owner_type, owner_id: owner_id, id: id }
        params[:name] = name if name
        params[:status] = status if status
        params[:config] = config if config
        rpc(:UpdateSink, params)
      end

      def delete_sink(owner_type:, owner_id:, id:)
        rpc(:DeleteSink, owner_type: owner_type, owner_id: owner_id, id: id)
      end

      private

      def twirp_class
        MonolithTwirp::ActionsDataStream::Core::V1::SinkAPIClient
      end
    end
  end
end
