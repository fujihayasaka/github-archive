# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/ability_models"

class Permissions::EnforcerTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @actor = AnActor.create
    @subject = ASubject.create
    @user = create(:user)
    @repo = create(:repository, :minimal, owner: @user)
  end

  context ".authorize" do
    test "not applicable by default when the action has been not been registered" do
      Permissions::Enforcer.stubs(:raise_on_error).returns(true)
      response = Permissions::Enforcer.authorize(actor: @actor, subject: @subject, action: :non_existent_action)

      assert_predicate response.decision, :not_applicable?
      refute_predicate response.decision, :allow?
    end

    test "version attribute is always present as part of the request, defaulting to LATEST" do
      attrs = Permissions::Enforcer.attrs_for(actor: @actor, subject: @subject, action: :non_existent_action)
      assert_includes attrs.map(&:id), Permissions::PolicyVersion::VERSION_ATTRIBUTE, "policy version should be provided by the enforcer by default"
      assert_equal attrs.find { |attr| attr.id == "version" }.value.integer_value, Permissions::PolicyVersion::LATEST
    end

    test "policy version is returned if present" do
      Permissions::PolicyVersion.stubs(:subject_agnostic_policy_versions).returns({ test: 9 })
      attrs = Permissions::Enforcer.attrs_for(actor: @actor, subject: @subject, action: :test)
      assert_equal attrs.find { |attr| attr.id == "version" }.value.integer_value, 9
    end

    test "policy version is returned if action is an array" do
      Permissions::PolicyVersion.stubs(:subject_agnostic_policy_versions).returns({ test: 9 })
      attrs = Permissions::Enforcer.attrs_for(actor: @actor, subject: @subject, action: [:test])
      assert_equal attrs.find { |attr| attr.id == "version" }.value.integer_value, 9
    end

    test "policy version is returned if all elements in array have same version" do
      Permissions::PolicyVersion.stubs(:subject_agnostic_policy_versions).returns({ test: 9, another: 9 })
      attrs = Permissions::Enforcer.attrs_for(actor: @actor, subject: @subject, action: [:test, :another])
      assert_equal attrs.find { |attr| attr.id == "version" }.value.integer_value, 9
    end

    test "latest if returned if all elements in array have no explicit version locking" do
      Permissions::PolicyVersion.stubs(:subject_agnostic_policy_versions).returns({})
      attrs = Permissions::Enforcer.attrs_for(actor: @actor, subject: @subject, action: [:test, :another])
      assert_equal attrs.find { |attr| attr.id == "version" }.value.integer_value, -1
    end

    test "raises if action array has actions with different versions" do
      Permissions::PolicyVersion.stubs(:subject_agnostic_policy_versions).returns({ test: 9, another: 8 })
      assert_raises Permissions::PolicyVersion::InvalidPolicyVersion do
        Permissions::Enforcer.attrs_for(actor: @actor, subject: @subject, action: [:test, :another])
      end
    end

    test "version passed via context overrides config in PolicyVersion" do
      Permissions::PolicyVersion.stubs(:versions).returns({ test: 9 })
      attrs = Permissions::Enforcer.attrs_for(actor: @actor, subject: @subject, action: :test, context: { version: 77 })
      assert_equal attrs.find { |attr| attr.id == "version" }.value.integer_value, 77
    end

    test "version attribute is not duplicated in payload if provided via enforcer context" do
      Permissions::PolicyVersion.stubs(:versions).returns({ test: 9 })
      attrs = Permissions::Enforcer.attrs_for(actor: @actor, subject: @subject, action: :test, context: { version: 77 })
      assert_equal 1, attrs.count { |attr| attr.id == "version" }
    end

    test "raises in dev/test if decision is INDETERMINATE" do
      Permissions::Authorizer.stubs(:authorize).returns(Authzd::Response.from_decision(Authzd::Proto::Decision.indeterminate))
      assert_raises RuntimeError do
        Permissions::Enforcer.authorize(actor: @actor, subject: @subject, action: :non_existent_action)
      end
    end

    test "raises in dev/test if decision is NOT_APPLICABLE" do
      Permissions::Authorizer.stubs(:authorize).returns(Authzd::Response.from_decision(Authzd::Proto::Decision.not_applicable))
      assert_raises RuntimeError do
        Permissions::Enforcer.authorize(actor: @actor, subject: @subject, action: :non_existent_action)
      end
    end

    test "can authorize a PORO subject" do
      subject = Registry::Container.new({ "id" => 3, "namespace" => @user.login })

      # Sends correct attributes
      attrs = Permissions::Enforcer.attrs_for(actor: @user, subject: subject, action: :read_package)
      assert_equal attrs.find { |attr| attr.id == "subject.type" }.value.string_value, "Package"
      assert_equal attrs.find { |attr| attr.id == "subject.id" }.value.integer_value, 3

      # Returns expected response
      Permissions::Authorizer.stubs(:authorize).returns(Authzd::Response.from_decision(Authzd::Proto::Decision.allow))
      response = Permissions::Enforcer.authorize(actor: @user, subject: subject, action: :read_package)
      assert_predicate response.decision, :allow?
    end

    test "authorize without enterprise teams when FF disabled" do
      GitHub.flipper[:enterprise_enforce_upfront_attribute].disable
      subject = create :business
      EnterpriseTeam.stubs(:all_team_ids_for).returns([42, 777])

      # Sends correct attributes
      attrs = Permissions::Enforcer.attrs_for(actor: @user, subject: subject, action: :manage_enterprise_security_products)
      assert_nil attrs.find { |attr| attr.id == "business.enterprise_teams.for_user" }

      # Returns expected response
      Permissions::Authorizer.stubs(:authorize).returns(Authzd::Response.from_decision(Authzd::Proto::Decision.deny))
      response = Permissions::Enforcer.authorize(actor: @user, subject: subject, action: :manage_enterprise_security_products)
      refute_predicate response.decision, :allow?
    end

    test "can authorize with enterprise teams" do
      GitHub.flipper[:enterprise_enforce_upfront_attribute].enable
      subject = create :business
      EnterpriseTeam.stubs(:all_visible_team_ids_for).with(@user, business_ids: [subject.id]).returns([42, 777])

      # Sends correct attributes
      attrs = Permissions::Enforcer.attrs_for(actor: @user, subject: subject, action: :manage_enterprise_security_products)
      assert_equal attrs.find { |attr| attr.id == "business.enterprise_teams.for_user" }.value.integer_list_value.values, [42, 777]

      # Returns expected response
      Permissions::Authorizer.stubs(:authorize).returns(Authzd::Response.from_decision(Authzd::Proto::Decision.allow))
      response = Permissions::Enforcer.authorize(actor: @user, subject: subject, action: :manage_enterprise_security_products)
      assert_predicate response.decision, :allow?
    end

    test "can authorize using cache for repeated requests" do
      GitHub.flipper[:permission_enforcer_with_caching].enable
      subject = Registry::Container.new({ "id" => 3, "namespace" => @user.login })

      attrs = Permissions::Enforcer.attrs_for(actor: @user, subject: subject, action: :read_package)
      assert_equal attrs.find { |attr| attr.id == "subject.type" }.value.string_value, "Package"
      assert_equal attrs.find { |attr| attr.id == "subject.id" }.value.integer_value, 3

      PermissionCache.enable do
        # expecting one authorize call
        Permissions::Authorizer.stubs(:authorize).once.returns(Authzd::Response.from_decision(Authzd::Proto::Decision.allow))
        response = Permissions::Enforcer.authorize(actor: @user, subject: subject, action: :read_package)
        assert_predicate response.decision, :allow?

        response = Permissions::Enforcer.authorize(actor: @user, subject: subject, action: :read_package)
        assert_predicate response.decision, :allow?
      end

      assert_dogstats_increment "ability.cache", tags: ["result:hit", "namespace:authzd_single"]
    end

    test "can authorize using cache for repeated requests with different actions" do
      GitHub.flipper[:permission_enforcer_with_caching].enable
      subject = Registry::Container.new({ "id" => 3, "namespace" => @user.login })

      attrs = Permissions::Enforcer.attrs_for(actor: @user, subject: subject, action: :read_package)
      assert_equal attrs.find { |attr| attr.id == "subject.type" }.value.string_value, "Package"
      assert_equal attrs.find { |attr| attr.id == "subject.id" }.value.integer_value, 3

      PermissionCache.enable do
        # expecting two authorize calls
        Permissions::Authorizer.stubs(:authorize).twice.returns(Authzd::Response.from_decision(Authzd::Proto::Decision.allow))
        response = Permissions::Enforcer.authorize(actor: @user, subject: subject, action: :read_package)
        assert_predicate response.decision, :allow?

        response = Permissions::Enforcer.authorize(actor: @user, subject: subject, action: :write_package)
        assert_predicate response.decision, :allow?
      end

      assert_dogstats_increment "ability.cache", tags: ["result:miss", "namespace:authzd_single"]
    end
  end

  context ".batch_authorize" do
    test "calls Authorizer#batch_authorize with Authzd::Proto::BatchRequest" do
      requests = [
        {
          actor: @actor,
          subject: @subject,
          action: "open_issue",
        },
        {
          actor: @actor,
          subject: @subject,
          action: "add_label",
        },
      ]

      req1 = Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(actor: requests[0][:actor], subject: requests[0][:subject], action: requests[0][:action]))
      req2 = Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(actor: requests[1][:actor], subject: requests[1][:subject], action: requests[1][:action]))

      requests2 = [req1, req2]
      batch_request = Authzd::Proto::BatchRequest.new(requests: requests2)
      dec1 = Authzd::Proto::Decision.allow
      dec2 = Authzd::Proto::Decision.deny
      decisions = [dec1, dec2]
      batch_decision = Authzd::Proto::BatchDecision.new(decisions: decisions)
      response = Authzd::BatchResponse.from_decision(batch_request, batch_decision)
      Permissions::Authorizer.expects(:batch_authorize).with(instance_of(Authzd::Proto::BatchRequest)).once.returns(response)
      Permissions::Enforcer.batch_authorize(requests: requests)
    end
  end

  context "cache" do
    test "calls Authorizer#batch_authorize with Authzd::Proto::BatchRequest with cache" do
      GitHub.flipper[:permission_enforcer_with_caching].enable

      requests = [
        {
          actor: @actor,
          subject: @subject,
          action: "open_issue",
        },
        {
          actor: @actor,
          subject: @subject,
          action: "add_label",
        },
      ]

      PermissionCache.enable do
        req1 = Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(actor: requests[0][:actor], subject: requests[0][:subject], action: requests[0][:action]))
        req2 = Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(actor: requests[1][:actor], subject: requests[1][:subject], action: requests[1][:action]))

        requests2 = [req1, req2]
        batch_request = Authzd::Proto::BatchRequest.new(requests: requests2)
        dec1 = Authzd::Proto::Decision.allow
        dec2 = Authzd::Proto::Decision.deny
        decisions = [dec1, dec2]
        expected_batch_decision = Authzd::Proto::BatchDecision.new(decisions: decisions)
        expected_response = Authzd::BatchResponse.from_decision(batch_request, expected_batch_decision)

        # expect only 1 call to authorize due to cache hit
        Permissions::Authorizer.expects(:batch_authorize).once.returns(expected_response)

        res1 = Permissions::Enforcer.batch_authorize(requests: requests)
        res2 = Permissions::Enforcer.batch_authorize(requests: requests)
        assert_equal res1.decisions, res2.decisions
      end

      assert_dogstats_increment "ability.cache", tags: ["result:hit", "namespace:authzd_batch"]
    end

    test "calls Authorizer#batch_authorize with Authzd::Proto::BatchRequest with partial cache" do
      GitHub.flipper[:permission_enforcer_with_caching].enable

      requests = [
        {
          actor: @actor,
          subject: @subject,
          action: "open_issue",
        },
        {
          actor: @actor,
          subject: @subject,
          action: "add_label",
        },
      ]

      PermissionCache.enable do
        req1 = Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(actor: requests[0][:actor], subject: requests[0][:subject], action: requests[0][:action]))
        req2 = Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(actor: requests[1][:actor], subject: requests[1][:subject], action: requests[1][:action]))

        requests2 = [req1, req2]
        batch_request = Authzd::Proto::BatchRequest.new(requests: requests2)
        dec1 = Authzd::Proto::Decision.allow
        dec2 = Authzd::Proto::Decision.deny
        decisions = [dec1, dec2]
        expected_batch_decision = Authzd::Proto::BatchDecision.new(decisions: decisions)
        expected_response = Authzd::BatchResponse.from_decision(batch_request, expected_batch_decision)

        # expect only 1 call to authorize due to cache hit
        expected_batch_decision_1 = Authzd::Proto::BatchDecision.new(decisions: [decisions[0]])
        expected_response_1 = Authzd::BatchResponse.from_decision(Authzd::Proto::BatchRequest.new(requests: [req1]), expected_batch_decision_1)
        Permissions::Authorizer.expects(:batch_authorize).once.returns(expected_response_1)

        res1 = Permissions::Enforcer.batch_authorize(requests: [requests[0]])

        # expect only 1 call to authorize due to cache hit
        Permissions::Authorizer.expects(:batch_authorize).once.returns(expected_response)
        res2 = Permissions::Enforcer.batch_authorize(requests: requests)
        assert_equal res1.decisions, expected_batch_decision_1.decisions
        assert_equal res2.decisions, expected_batch_decision.decisions
      end

      assert_dogstats_increment "ability.cache", tags: ["result:partial", "namespace:authzd_batch"]
    end

    test "calls Authorizer#batch_authorize with Authzd::Proto::BatchRequest with cache miss" do
      GitHub.flipper[:permission_enforcer_with_caching].enable

      requests = [
        {
          actor: @actor,
          subject: @subject,
          action: "open_issue",
        },
        {
          actor: @actor,
          subject: @subject,
          action: "add_label",
        },
      ]

      PermissionCache.enable do
        req1 = Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(actor: requests[0][:actor], subject: requests[0][:subject], action: requests[0][:action]))
        req2 = Authzd::Proto::Request.new(attributes: Permissions::Enforcer.attrs_for(actor: requests[1][:actor], subject: requests[1][:subject], action: requests[1][:action]))

        batch_request1 = Authzd::Proto::BatchRequest.new(requests: [req1])
        dec1 = Authzd::Proto::Decision.allow
        dec2 = Authzd::Proto::Decision.deny

        expected_batch_decision1 = Authzd::Proto::BatchDecision.new(decisions: [dec1])
        expected_response1 = Authzd::BatchResponse.from_decision(batch_request1, expected_batch_decision1)
        expected_batch_decision2 = Authzd::Proto::BatchDecision.new(decisions: [dec2])
        expected_response2 = Authzd::BatchResponse.from_decision(Authzd::Proto::BatchRequest.new(requests: [req2]), expected_batch_decision2)

        Permissions::Authorizer.expects(:batch_authorize).once.returns(expected_response1)
        res1 = Permissions::Enforcer.batch_authorize(requests: [requests[0]])

        Permissions::Authorizer.expects(:batch_authorize).once.returns(expected_response2)
        res2 = Permissions::Enforcer.batch_authorize(requests: [requests[1]])

        assert_equal res1.decisions, expected_batch_decision1.decisions
        assert_equal res2.decisions, expected_batch_decision2.decisions
      end

      assert_dogstats_increment "ability.cache", tags: ["result:miss", "namespace:authzd_batch"]
    end
  end

  context "considers_site_admin" do
    test "defaults to false when not provided" do
      attrs = Permissions::Enforcer.attrs_for(actor: @user, subject: @repo, action: :test)
      refute attrs.find { |attr| attr.id == "considers_site_admin" }.value.bool_value
      refute_nil attrs.find { |attr| attr.id == "considers_site_admin" }.value.bool_value
    end

    test "true when provided" do
      attrs = Permissions::Enforcer.attrs_for(actor: @user, subject: @repo, action: :test, context: { considers_site_admin: true })
      assert attrs.find { |attr| attr.id == "considers_site_admin" }.value.bool_value
    end

    test "the attribute is not coerced twice" do
      attrs = Permissions::Enforcer.attrs_for(actor: @user, subject: @repo, action: :test, context: { considers_site_admin: true })
      assert_equal 1, attrs.count { |attr| attr.id == "considers_site_admin" }
    end
  end
end
