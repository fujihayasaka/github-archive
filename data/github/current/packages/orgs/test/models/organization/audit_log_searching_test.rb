# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationAuditLogSearchingTest < GitHub::TestCase
  random_org_id = rand(10000..1000000)
  fixtures do
    @org = create(:organization, id: random_org_id)
  end

  test "audit_log_query" do
    query = "((_exists_:org AND org_id:#{random_org_id}) OR user_id:#{random_org_id} OR actor_id:#{random_org_id} OR data.old_user_id:#{random_org_id})"
    assert_equal query, @org.audit_log_query
  end
end
