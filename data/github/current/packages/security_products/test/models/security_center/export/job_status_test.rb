# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Export
    class JobStatusTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @org = create(:organization, admin: @user)
      end

      context ".create" do
        test "creates a JobStatus with the correct context" do
          query = "archived:false"
          requested_at = Time.new(2024, 2, 2)
          start_date = Date.new(2024, 1, 1)
          end_date = Date.new(2024, 2, 2)
          status = SecurityCenter::Export::JobStatus.create(id: "123", query:, scope: @org, requester: @user, requested_at:, start_date:, end_date:)

          refute_nil status
          assert_equal query, status.query
          assert_equal @org.id, status.scope_id
          assert_equal "Organization", status.scope_type
          assert_equal @user.id, status.requester_id
          assert_equal requested_at.utc.to_s, status.requested_at
          assert_equal start_date.to_s, status.start_date
          assert_equal end_date.to_s, status.end_date
          assert_equal SecurityCenter::Export::JobStatus::QUEUED_JOB_TTL.to_i, status.ttl
        end
      end
    end
  end
end
