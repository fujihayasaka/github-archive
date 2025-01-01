# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ClosedIssueEvents < Platform::Loader
      sig do
        params(
          issue_id: T.nilable(Integer),
          omit_event_detail: T::Boolean,
          fields: T::Array[Symbol],
          order: String,
          limit: T.nilable(Integer),
        ).returns(
          Promise[T.nilable(T::Array[::IssueEvent])]
        )
      end
      def self.load(issue_id, omit_event_detail: false, fields: [], order: "ASC", limit: nil)
        self.for(omit_event_detail: omit_event_detail, fields: fields, order: order, limit: limit).load(issue_id)
      end

      sig do
        params(
          issue_ids: T::Array[Integer],
          omit_event_detail: T::Boolean,
          fields:  T::Array[Symbol],
          order:  String,
        ).returns(
          Promise[T::Hash[Integer, T.nilable(::IssueEvent)]],
        )
      end
      def self.load_all(issue_ids, omit_event_detail: false, fields: [], order: "ASC")
        loader = self.for(omit_event_detail: omit_event_detail, fields: fields, order: order)
        Promise.all(
          issue_ids.map { |id| loader.load(id).then { |events| [id, events&.first] } }
        ).then { |map| map.to_h }
      end

      sig { params(omit_event_detail: T::Boolean, fields:  T::Array[Symbol], order: String, limit: T.nilable(Integer)).void }
      def initialize(omit_event_detail: false, fields: [], order: "ASC", limit: nil)
        @omit_event_detail = omit_event_detail
        @fields = fields.empty? ? ["*"] : (fields << :issue_id).uniq
        @order = order if %w[ASC DESC].include?(order)
        @limit = limit
      end

      sig do
        params(
          issue_ids: T::Array[Integer]
        ).returns(
         T::Hash[Integer, T.nilable(T::Array[::IssueEvent])]
        )
      end
      def fetch(issue_ids)
        scope = if @omit_event_detail
          ::IssueEvent.unscoped.select(*@fields)
        else
          ::IssueEvent.select(*@fields)
        end

        scope = scope.where(issue_id: issue_ids, event: "closed")

        scope = scope.order("id #{@order}")

        scope = scope.limit(@limit) if @limit.present?

        scope.group_by(&:issue_id)
      end
    end
  end
end
