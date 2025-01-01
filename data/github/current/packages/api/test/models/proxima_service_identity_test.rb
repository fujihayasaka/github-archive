# typed: true
# frozen_string_literal: true

require "test_helper"

class ProximaServiceIdentityTest < GitHub::TestCase
  test "default_rate_limits" do
    assert_equal 5000, ProximaServiceIdentity.default_rate_limit("actions")
    assert_equal 5000, ProximaServiceIdentity.default_rate_limit("dependabot")
    assert_raises do
      ProximaServiceIdentity.default_rate_limit("not_a_valid_service")
    end
  end

  test "attributes" do
    ProximaServiceIdentity.new(tenant_shortcode: "tenant-1", service_name: "actions", rate_limit: 1000).save

    pti = ProximaServiceIdentity.find_by(tenant_shortcode: "tenant-1")
    assert_equal "tenant-1", T.unsafe(pti).tenant_shortcode
    assert_equal "actions", T.unsafe(pti).service_name
    assert_equal 1000, T.unsafe(pti).rate_limit
  end

  test "service_name validation" do
    assert ProximaServiceIdentity.new(tenant_shortcode: "tenant-1", service_name: "actions", rate_limit: 1000).valid?
    assert ProximaServiceIdentity.new(tenant_shortcode: "tenant-1", service_name: "dependabot", rate_limit: 1000).valid?
    refute ProximaServiceIdentity.new(tenant_shortcode: "tenant-1", service_name: "not_a_valid_service", rate_limit: 1000).valid?
  end

  context "audit log events" do
    test "#create" do
      events = subscribe "proxima_service_rate_limit.create"

      psi = ProximaServiceIdentity.create(tenant_shortcode: "tenant-1", service_name: "actions", rate_limit: 10000)

      assert event = events.pop
      assert_equal psi.id, event.payload[:registration_id]
      assert_equal "tenant-1", event.payload[:tenant]
      assert_equal "actions", event.payload[:service]
      assert_equal 10000, event.payload[:rate_limit]
    end

    test "#update" do
      psi = ProximaServiceIdentity.create(tenant_shortcode: "tenant-1", service_name: "actions", rate_limit: 10000)

      events = subscribe "proxima_service_rate_limit.update"

      psi.update(rate_limit: 20000)

      assert event = events.pop
      assert_equal psi.id, event.payload[:registration_id]
      assert_equal "tenant-1", event.payload[:tenant]
      assert_equal "actions", event.payload[:service]
      assert_equal 20000, event.payload[:rate_limit]
    end

    test "#destroy" do
      psi = ProximaServiceIdentity.create(tenant_shortcode: "tenant-1", service_name: "actions", rate_limit: 10000)

      events = subscribe "proxima_service_rate_limit.destroy"

      psi.destroy

      assert event = events.pop
      assert_equal psi.id, event.payload[:registration_id]
      assert_equal "tenant-1", event.payload[:tenant]
      assert_equal "actions", event.payload[:service]
      assert_equal 10000, event.payload[:rate_limit]
    end
  end
end
