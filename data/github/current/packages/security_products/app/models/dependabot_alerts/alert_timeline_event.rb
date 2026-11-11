# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class AlertTimelineEvent
    sig { returns(T.nilable(Symbol)) }
    attr_reader :type

    sig { returns(T.nilable(Integer)) }
    attr_reader :user_id

    sig { returns(T.nilable(Google::Protobuf::Timestamp)) }
    attr_reader :timestamp

    sig { returns(T.nilable(String)) }
    attr_reader :resolution

    sig { returns(T.nilable(String)) }
    attr_reader :resolution_note

    sig { returns(T.nilable(Integer)) }
    attr_reader :request_id

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :show_dismissal_actions

    sig { returns(T.nilable(String)) }
    attr_reader :compute_status

    sig { returns(T.nilable(String)) }
    attr_reader :reviewer_comment

    sig do
      params(
        type: T.nilable(Symbol),
        user_id: T.nilable(Integer),
        timestamp: T.nilable(Google::Protobuf::Timestamp),
        resolution: T.nilable(String),
        resolution_note: T.nilable(String),
        request_id: T.nilable(Integer),
        show_dismissal_actions: T.nilable(T::Boolean),
        compute_status: T.nilable(String),
        reviewer_comment: T.nilable(String)
      ).void
    end
    def initialize(type: nil, user_id: nil, timestamp: nil, resolution: nil, resolution_note: nil, request_id: nil, show_dismissal_actions: nil, compute_status: nil, reviewer_comment: nil)
      @type = type
      @user_id = user_id
      @timestamp = timestamp
      @resolution = resolution
      @resolution_note = resolution_note
      @request_id = request_id
      @show_dismissal_actions = show_dismissal_actions
      @compute_status = compute_status
      @reviewer_comment = reviewer_comment
    end
  end
end
