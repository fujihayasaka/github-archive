# typed: strict
# frozen_string_literal: true

module Copilot
  class Activity
    extend T::Helpers

    sig { returns(Integer) }
    attr_reader :user_id

    sig { returns(String) }
    attr_reader :editor_details

    sig { returns(Time) }
    attr_reader :activity_date

    sig do
      params(
        user_id: Integer,
        editor_details: String,
        activity_date: Time,
      ).void
    end
    def initialize(user_id:, editor_details:, activity_date:)
      @user_id        = T.let(user_id, Integer)
      @editor_details = T.let(editor_details, String)
      @activity_date  = T.let(activity_date, Time)
    end

    sig { params(user_id: Integer).returns(T.nilable(Copilot::Activity)) }
    def self.find_for_user_id(user_id)
      details = Copilot.redis.hgetall("last_activity:#{user_id}")

      unless details.empty?
        # if it's not empty, it's gonna be in this shape
        # {"editor_details"=>"vscode/1.92.0/", "source"=>"copilot_v0_copilot_event", "activity_date"=>"2024-08-09T09:34:40.077Z", "user_id"=>"22348", "integration_id"=>"vscode-chat"}
        new(
          user_id: user_id,
          editor_details: details["editor_details"].to_s,
          # activity date needs to be parsed in UTC
          activity_date: Time.parse(details["activity_date"].to_s).utc,
        )
      end
    end
  end
end
