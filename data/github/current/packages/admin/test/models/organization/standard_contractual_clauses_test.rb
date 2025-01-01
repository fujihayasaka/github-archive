# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.enterprise?
  class OrganizationStandardContractualClausesTest < GitHub::TestCase

    fixtures do
      @org   = create(:organization)
      @staff = create(:staff_admin_user)
    end

    test "flagging sets the flag on the organization" do
      refute @org.standard_contractual_clauses?
      @org.flag_for_standard_contractual_clauses!(actor: @staff)
      assert @org.standard_contractual_clauses?
    end

    test "flagging creates an audit log event" do
      events = subscribe "staff.flag_for_standard_contractual_clauses"

      expected_payload = {
        staff_actor:    @staff.login,
        staff_actor_id: @staff.id,
        actor:          User.staff_user.login,
        actor_id:       User.staff_user.id,
        org:            @org.login,
        org_id:         @org.id,
      }

      @org.flag_for_standard_contractual_clauses!(actor: @staff)

      assert event = events.pop, "an event was expected"
      assert_equal "staff.flag_for_standard_contractual_clauses", event.name
      assert_equal expected_payload, event.payload
    end

    test "removing unsets the flag on the organization" do
      @org.flag_for_standard_contractual_clauses!(actor: @staff)
      @org.remove_standard_contractual_clauses_flag!(actor: @staff)
      refute @org.standard_contractual_clauses?
    end

    test "unflagging creates an audit log event" do
      events = subscribe "staff.remove_standard_contractual_clauses_flag"
      @org.flag_for_standard_contractual_clauses!(actor: @staff)

      expected_payload = {
        staff_actor:    @staff.login,
        staff_actor_id: @staff.id,
        actor:          User.staff_user.login,
        actor_id:       User.staff_user.id,
        org:            @org.login,
        org_id:         @org.id,
      }

      @org.remove_standard_contractual_clauses_flag!(actor: @staff)

      assert event = events.pop, "an event was expected"
      assert_equal "staff.remove_standard_contractual_clauses_flag", event.name
      assert_equal expected_payload, event.payload
    end
  end
end
