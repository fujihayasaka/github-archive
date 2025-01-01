# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueTypeEventVisibleCheck < Platform::Loader
      sig { params(viewer: User, event_id: Integer).returns(Promise[T::Boolean]) }
      def self.load(viewer, event_id)
        self.for(viewer).load(event_id)
      end

      sig { params(viewer: User).void }
      def initialize(viewer)
        @viewer = viewer
        @issue_types = {}
      end

      sig { params(id: Integer).returns(Promise[T.nilable(IssueType)]) }
      def issue_type(id)
        if @issue_types[id].present?
          Promise.resolve(@issue_types[id])
        else
          Loaders::ActiveRecord.load(::IssueType, id).then do |issue_type|
            next unless issue_type
            @issue_types[id] = issue_type
            issue_type
          end
        end
      end

      sig { params(event_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Boolean]) }
      def fetch(event_ids)
        issue_events = IssueEvent.where(id: event_ids).includes([:issue_event_detail, repository: :owner])
        result = Hash.new(false)

        Promise.all(issue_events.map do |issue_event|
          next unless owner = issue_event.repository&.owner
          next unless owner.is_a?(Organization)

          owner.async_business.then do
            event_detail = T.cast(issue_event.issue_event_detail, IssueEventDetail)
            event_id = issue_event.id

            matrix = T.cast(owner, Organization).async_readable_issue_types_matrix(@viewer).then do |matrix|
              case issue_event.event
              when "issue_type_added"
                next unless issue_event.issue_type_id
                build_issue_type(issue_event.issue_type_id, owner, event_detail).then do |issue_type|
                  next unless issue_type.enabled?
                  issue_type.readable?(matrix).then do |readable|
                    result[event_id] = readable
                  end
                end
              when "issue_type_removed"
                next unless issue_event.prev_issue_type_id
                build_prev_issue_type(issue_event.prev_issue_type_id, owner, event_detail).then do |prev_issue_type|
                  next unless prev_issue_type.enabled?
                  prev_issue_type.readable?(matrix).then do |readable|
                    result[event_id] = readable
                  end
                end
              when "issue_type_changed"
                next unless issue_event.issue_type_id && issue_event.prev_issue_type_id
                Promise.all([
                  build_issue_type(issue_event.issue_type_id, owner, event_detail),
                  build_prev_issue_type(issue_event.prev_issue_type_id, owner, event_detail)
                ]).then do |issue_type, prev_issue_type|
                  next unless issue_type.enabled? && prev_issue_type.enabled?
                  Promise.all([
                    issue_type.readable?(matrix),
                    prev_issue_type.readable?(matrix)
                  ]).then do |readable_issue_type, readable_prev_issue_type|
                    result[event_id] = readable_issue_type && readable_prev_issue_type
                  end
                end
              else
                next nil
              end
            end
          end
        end).sync

        result
      end

      sig { params(issue_type_id: Integer, owner: User, event_detail: IssueEventDetail).returns(Promise[IssueType]) }
      def build_issue_type(issue_type_id, owner, event_detail)
        issue_type(issue_type_id).then do |loaded_issue_type|
          loaded_issue_type ||
          ::IssueType.new(
            created_at: event_detail.created_at,
            id: event_detail.issue_type_id || 0,
            name: event_detail.issue_type_name,
            color: event_detail.issue_type_color,
            owner:,
          )
        end
      end

      sig { params(issue_type_id: Integer, owner: User, event_detail: IssueEventDetail).returns(Promise[IssueType]) }
      def build_prev_issue_type(issue_type_id, owner, event_detail)
        issue_type(issue_type_id).then do |loaded_issue_type|
          loaded_issue_type ||
          ::IssueType.new(
            created_at: event_detail.created_at,
            id: event_detail.prev_issue_type_id || 0,
            name: event_detail.prev_issue_type_name,
            color: event_detail.prev_issue_type_color,
            owner:,
          )
        end
      end
    end
  end
end
