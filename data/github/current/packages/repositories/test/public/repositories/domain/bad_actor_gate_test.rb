# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::BadActorGateTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  class TestDomain < GH::Domain::Base

    include Repositories::Domain::BadActorGate

    def foo(owner_id:)
      check_domain_bad_actor_gate!(owner_id:, method_name: T.must(__method__))
      "foo"
    end

    def bar(owner_id:)
      check_domain_bad_actor_gate!(owner_id:, method_name: T.must(__method__))
      "bar"
    end
  end

  fixtures do
    @user = create(:user)
    @another_user = create(:user)
    @owner = create(:organization)
    @another_owner = create(:organization)
  end

  test "flipper id for domain method actor" do
    assert_equal(
      "Repositories::Domain::BadActorGateTest::TestDomain::Owner:#{@owner.id}::Actor:#{@user.id}::foo",
      Repositories::Domain::BadActorGate::DomainMethodActor.new(
        T.must(TestDomain.name),
        :foo,
        @user.id,
        @owner.id
      ).flipper_id
    )
  end

  test "do not block if actor is not provided" do
    domain_method_actor = Repositories::Domain::BadActorGate::DomainMethodActor.new(
      T.must(TestDomain.name),
      :foo,
      @user.id,
      @owner.id
    )

    GitHub.flipper[:repos_domain_bad_actor_gate].enable(domain_method_actor)

    assert_equal "foo", domain.foo(owner_id: @owner.id)
    assert_equal "bar", domain.bar(owner_id: @owner.id)

    GitHub.flipper[:repos_domain_bad_actor_gate].disable
  end

  test "do not block if FF is dark shipped" do
    GitHub.flipper[:repos_domain_bad_actor_gate].enable

    assert_equal "foo", domain.foo(owner_id: @owner.id)
    assert_equal "bar", domain.bar(owner_id: @owner.id)
  end

  test "raise for the correct method when gate is closed" do
    foo_domain_method_actor = Repositories::Domain::BadActorGate::DomainMethodActor.new(
      T.must(TestDomain.name),
      :foo,
      @user.id,
      @owner.id
    )

    bar_domain_method_actor = Repositories::Domain::BadActorGate::DomainMethodActor.new(
      T.must(TestDomain.name),
      :bar,
      @user.id,
      @owner.id
    )

    GitHub.flipper[:repos_domain_bad_actor_gate].enable(foo_domain_method_actor)

    act_as(@user)
    assert_raises(Repositories::Domain::BadActorGate::Error::UnprocessableEntity) { domain.foo(owner_id: @owner.id) }
    act_as(@another_user)
    assert_equal "foo", domain.foo(owner_id: @owner.id)
    act_as(@user)
    assert_equal "foo", domain.foo(owner_id: @another_owner.id)
    assert_equal "bar", domain.bar(owner_id: @owner.id)

    GitHub.flipper[:repos_domain_bad_actor_gate].disable(foo_domain_method_actor)
    GitHub.flipper[:repos_domain_bad_actor_gate].enable(bar_domain_method_actor)

    assert_equal "foo", domain.foo(owner_id: @owner.id)
    assert_raises(Repositories::Domain::BadActorGate::Error::UnprocessableEntity) { domain.bar(owner_id: @owner.id) }
    act_as(@another_user)
    assert_equal "bar", domain.bar(owner_id: @owner.id)
    act_as(@user)
    assert_equal "bar", domain.bar(owner_id: @another_owner.id)

    GitHub.flipper[:repos_domain_bad_actor_gate].disable(bar_domain_method_actor)

    assert_equal "foo", domain.foo(owner_id: @owner.id)
    assert_equal "bar", domain.bar(owner_id: @owner.id)
  end

  test "telemetry" do
    foo_domain_method_actor = Repositories::Domain::BadActorGate::DomainMethodActor.new(
      T.must(TestDomain.name),
      :foo,
      @user.id,
      @owner.id
    )

    GitHub.flipper[:repos_domain_bad_actor_gate].enable(foo_domain_method_actor)

    assert_logged("code.namespace": "Repositories::Domain::BadActorGateTest::TestDomain") do
      assert_raises(Repositories::Domain::BadActorGate::Error::UnprocessableEntity) do
        act_as(@user)
        domain.foo(owner_id: @owner.id)
        assert_dogstats_count_value 1, "domain.bad_actor_gate", tags: ["domain:#{T.must(TestDomain.name)}", "method:foo"]
      end
    end
  end

  def domain
    TestDomain.new
  end
end
