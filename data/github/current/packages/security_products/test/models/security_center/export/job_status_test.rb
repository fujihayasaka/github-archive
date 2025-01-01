# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Export
    class JobStatusTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
      end

      context ".create" do
        test "creates a JobStatus with the correct context" do
          query = "archived:false"
          requested_at = Time.new(2024, 2, 2)
          start_date = Date.new(2024, 1, 1)
          end_date = Date.new(2024, 2, 2)
          status = JobStatus.create(id: "123", user: @user, query: , requested_at:, start_date:, end_date:)

          refute_nil status
          assert_equal query, status.query
          assert_equal requested_at.utc.to_s, status.requested_at
          assert_equal start_date.to_s, status.start_date
          assert_equal end_date.to_s, status.end_date
        end
      end
    end
  end
end
