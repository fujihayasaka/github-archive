# typed: false
# frozen_string_literal: true

require "test_helper"

class FilterTest < GitHub::TestCase
  include DogstatsTestHelpers
  include PerformanceTestHelpers

  # A class to test ConditionalAccess::Filter
  class TestFilter < ::ConditionalAccess::Filter

    attr_reader :user

    def initialize(callback, user, do_authzd_science: false)
      @user = user
      super(callback, do_authzd_science:)
    end

    def conditional_access_policies
      [:membership, :first_letter_a, :notapplicable]
    end

    def authzd_science_policies
      [:first_letter_a]
    end

    def authzd_cap_actor
      {}
    end

    def authzd_cap_request_attributes
      {}
    end

    def multiple_membership_satisfied(targets, target_provider)
      result = Hash.new { |h, k| h[k] = {} }
      targets.map do |target|
        result[target] = {
          "private": target.member?(user) ? :satisfied : :unsatisfied,
        }
      end
      result
    end

    def multiple_first_letter_a_satisfied(targets, target_provider)
      result = Hash.new { |h, k| h[k] = {} }
      targets.map do |target|
        result[target] = {
          "private": target.name.start_with?("a") ? :satisfied : :unsatisfied,
        }
      end
      result
    end

    def multiple_notapplicable_applicable(targets, target_provider)
      []
    end

    def location
      :test
    end
  end

  class NoPolicyFilter < ::ConditionalAccess::Filter
    def location
      :test
    end

    def callback_name
      "Object"
    end
  end

  fixtures do
    @org1 = create(:organization, login: "a1")
    @repo1 = create(:repository, owner: @org1)
    @org2 = create(:organization, login: "a2")
    @repo2 = create(:repository, owner: @org2)
    @org3 = create(:organization, login: "b")
    @repo3 = create(:repository, owner: @org3)

    @user = create(:user)
    @org1.add_member(@user)
    @org3.add_member(@user)
  end

  setup do
    # Initialize a filter in each test since a lot of these tests
    # use mocked out policy methods, and the caching messes with it.
    @filter = TestFilter.new(self, @user)
    GitHub::Experiment.raise_on_mismatches = false
  end

  def all_repos_sorted
    Repository.all.sort_by(&:id)
  end

  context "evaluate" do
    test "produces ResultSet containing all resources passed in" do
      results = @filter.evaluate(Repository.all)
      assert_same_elements [@repo1, @repo2, @repo3], results.resources
      assert_dogstats_count_value 1, "cap.filter.executed", tags: ["success:true", "error:"]
    end

    test "accepts array of ActiveRecords" do
      results = @filter.evaluate(Repository.all.to_a)
      assert_same_elements [@repo1, @repo2, @repo3], results.resources
    end

    test "accepts single ActiveRecord object" do
      results = @filter.evaluate(@repo1)
      assert_same_elements [@repo1], results.resources
    end

    test "returns empty ResultSet with nil resources" do
      results = @filter.evaluate(nil)
      assert results.empty?
      assert_same_elements [], results.resources
    end

    test "produces ResultSet that can yield only authorized resources" do
      results = @filter.evaluate(Repository.all)
      assert_same_elements [@repo1], results.authorized.resources
    end

    test "produces ResultSet that can yield only resources authorized by specific policy" do
      results = @filter.evaluate(Repository.all)
      assert_same_elements [@repo1, @repo3], results.authorized(only: :membership).resources
      assert_same_elements [@repo1, @repo2], results.authorized(only: :first_letter_a).resources
    end

    test "produces ResultSet with expected policy results" do
      actual = @filter.evaluate(Repository.all)

      expected = ConditionalAccess::ResultSet::new([
          ConditionalAccess::Result::new(@repo1, Hash[
            :membership,     Hash[:private, :satisfied],
            :first_letter_a, Hash[:private, :satisfied],
            :notapplicable,  Hash[:private, :inapplicable]]),
          ConditionalAccess::Result::new(@repo2, Hash[
            :membership,     Hash[:private, :unsatisfied],
            :first_letter_a, Hash[:private, :satisfied],
            :notapplicable,  Hash[:private, :inapplicable]]),
          ConditionalAccess::Result::new(@repo3, Hash[
            :membership,     Hash[:private, :satisfied],
            :first_letter_a, Hash[:private, :unsatisfied],
            :notapplicable,  Hash[:private, :inapplicable]]),
        ])
      assert_same_elements expected.results, actual.results
    end

    test "produces ResultSet that can yield only unauthorized resources" do
      results = @filter.evaluate(Repository.all)
      assert_same_elements [@repo2, @repo3], results.unauthorized.resources
    end

    test "produces ResultSet that can yield only resources rejected by specific policy" do
      results = @filter.evaluate(Repository.all)
      assert_same_elements [@repo2], results.unauthorized(only: :membership).resources
      assert_same_elements [@repo3], results.unauthorized(only: :first_letter_a).resources
    end

    test "passing only ensures only that policy is represented in the results" do
      results = @filter.evaluate(Repository.all, only: [:membership])
      assert_same_elements [@repo2], results.unauthorized.resources
      assert_same_elements [@repo1, @repo3], results.authorized.resources
    end

    test "passing exclude ensures that the specified policy is not represented in the results" do
      results = @filter.evaluate(Repository.all, exclude: [:membership])
      assert_same_elements [@repo3], results.unauthorized.resources
      assert_same_elements [@repo1, @repo2], results.authorized.resources
    end

    test "passing only defines policies to execute" do
      @filter.stubs(:conditional_access_policies).returns([:called, :not_called])
      org_hash = {
        @org1 => Hash[:private, :satisfied],
        @org2 => Hash[:private, :satisfied],
        @org3 => Hash[:private, :satisfied]
      }
      @filter.expects(:multiple_called_satisfied).returns(org_hash).at_least_once
      @filter.evaluate(Repository.all, only: :called)
    end

    test "passing exclude defines to avoid" do
      @filter.stubs(:conditional_access_policies).returns([:called, :not_called])
      org_hash = {
        @org1 => Hash[:private, :satisfied],
        @org2 => Hash[:private, :satisfied],
        @org3 => Hash[:private, :satisfied]
      }
      @filter.expects(:multiple_called_satisfied).returns(org_hash).at_least_once
      @filter.evaluate(Repository.all, exclude: :not_called)
    end

    test "exclude substracts from only" do
      @filter.stubs(:conditional_access_policies).returns([:one, :two, :three])
      org_hash = {
        @org1 => Hash[:private, :satisfied],
        @org2 => Hash[:private, :satisfied],
        @org3 => Hash[:private, :satisfied]
      }
      @filter.expects(:multiple_one_satisfied).returns(org_hash).at_least_once
      @filter.expects(:multiple_two_satisfied).returns(org_hash).at_least_once
      @filter.evaluate(Repository.all, only: [:one, :two, :three], exclude: [:three])
    end

    test "raises if only+exclude leads to no policies" do
      err = assert_raises ConditionalAccess::Filter::Error do
        @filter.evaluate(Repository.all, only: :one, exclude: :one)
      end
      assert_match /no policies defined/, err.message
      assert_dogstats_count_value 1, "cap.filter.executed", tags: ["success:false", "error:ConditionalAccess::Filter::Error"]
    end

    test "raises if filter does not define policies to apply" do
      err = assert_raises ConditionalAccess::Filter::Error do
        NoPolicyFilter.new(self).evaluate(Repository.all)
      end
      assert_match /conditional_access_policies/, err.message
      assert_dogstats_count_value 1, "cap.filter.executed", tags: ["success:false", "error:ConditionalAccess::Filter::Error"]
    end

    test "fails closed if policy logic is not defined" do
      @filter.stubs(:conditional_access_policies).returns([:invalid])
      results = @filter.evaluate(Repository.all)
      assert_empty results.authorized.resources
    end

    test "caching produces same results" do
      inputs = [@repo1, @repo2, @repo3]
      targets = [@org1, @org2, @org3]
      expected = ConditionalAccess::ResultSet::new([
        ConditionalAccess::Result::new(@repo1, Hash[
          :membership,     Hash[:private, :satisfied],
          :first_letter_a, Hash[:private, :satisfied],
          :notapplicable,  Hash[:private, :inapplicable]]),
        ConditionalAccess::Result::new(@repo2, Hash[
          :membership,     Hash[:private, :unsatisfied],
          :first_letter_a, Hash[:private, :satisfied],
          :notapplicable,  Hash[:private, :inapplicable]]),
        ConditionalAccess::Result::new(@repo3, Hash[
          :membership,     Hash[:private, :satisfied],
          :first_letter_a, Hash[:private, :unsatisfied],
          :notapplicable,  Hash[:private, :inapplicable]]),
      ])
      membership_hash = {
        @org1 => Hash[:private, :satisfied],
        @org3 => Hash[:private, :satisfied]
      }
      letter_a_hash = {
        @org1 => Hash[:private, :satisfied],
        @org2 => Hash[:private, :satisfied]
      }
      @filter.expects(:multiple_membership_satisfied).with(targets, instance_of(ConditionalAccess::TargetProvider)).returns(membership_hash).at_most_once
      @filter.expects(:multiple_first_letter_a_satisfied).with(targets, instance_of(ConditionalAccess::TargetProvider)).returns(letter_a_hash).at_most_once
      @filter.expects(:multiple_notapplicable_applicable).with(targets, instance_of(ConditionalAccess::TargetProvider)).returns([]).at_most_once

      assert_equal expected, @filter.evaluate(inputs)
      assert_equal expected, @filter.evaluate(inputs)
    end

    test "caching works per-policy and per-resource" do
      inputs = [@repo1, @repo2, @repo3]
      targets = [@org1, @org2, @org3]
      expected = ConditionalAccess::ResultSet::new([
        ConditionalAccess::Result::new(@repo1, Hash[
          :membership,     Hash[:private, :satisfied],
          :first_letter_a, Hash[:private, :satisfied],
          :notapplicable,  :inapplicable]),
        ConditionalAccess::Result::new(@repo2, Hash[
          :membership,     Hash[:private, :unsatisfied],
          :first_letter_a, Hash[:private, :satisfied],
          :notapplicable,  :inapplicable]),
        ConditionalAccess::Result::new(@repo3, Hash[
          :membership,     Hash[:private, :satisfied],
          :first_letter_a, Hash[:private, :unsatisfied],
          :notapplicable,  :inapplicable]),
      ])
      membership_hash = {
        @org1 => Hash[:private, :satisfied],
        @org3 => Hash[:private, :satisfied]
      }
      @filter.expects(:multiple_membership_satisfied).with([@org1, @org2, @org3], instance_of(ConditionalAccess::TargetProvider)).returns(membership_hash).once
      @filter.expects(:multiple_notapplicable_applicable).with([@org1, @org3], instance_of(ConditionalAccess::TargetProvider)).returns([]).once
      @filter.expects(:multiple_notapplicable_applicable).with([@org2], instance_of(ConditionalAccess::TargetProvider)).returns([]).once
      @filter.expects(:multiple_first_letter_a_satisfied).with([@org2], instance_of(ConditionalAccess::TargetProvider)).returns({ @org2 => Hash[:private, :satisfied] }).once
      @filter.expects(:multiple_first_letter_a_satisfied).with([@org1, @org3], instance_of(ConditionalAccess::TargetProvider)).returns(membership_hash).once

      assert_same_elements [@repo1, @repo3], @filter.evaluate([@repo1, @repo2, @repo3], only: :membership).authorized.resources
      assert_same_elements [@repo1, @repo3], @filter.evaluate([@repo1, @repo3], exclude: :first_letter_a).authorized.resources
      assert_same_elements [], @filter.evaluate([@repo2]).authorized.resources
      assert_same_elements [@repo1, @repo3], @filter.evaluate([@repo1, @repo2, @repo3]).authorized.resources
    end
  end

  context "authzd science" do
    test "increments mismatch metric when authzd error" do
      skip unless GitHub.flipper[:run_authzd_cap_filter_experiment].enabled?

      filter = TestFilter.new(self, @user, do_authzd_science: true)
      GitHub::Experiment.raise_on_mismatches = true

      assert_raises Scientist::Experiment::MismatchError do
        filter.evaluate(all_repos_sorted)
      end
      assert_dogstats_count_value(1, "cap_extraction_filter_experiment_generic_mismatch", tags: ["error:server_error"])
    end

    test "cleans science results with same values" do
      diff = ::ConditionalAccess::Filter.clean_science_result({
        @repo1 => { policy_a: :unsatisfied },
        @repo2 => { policy_a: :unsatisfied },
        @repo3 => { policy_a: :unsatisfied },
      }, {
        @repo1 => { policy_a: :unsatisfied },
        @repo2 => { policy_a: :unsatisfied },
        @repo3 => { policy_a: :unsatisfied },
      })

      assert_same_hash({}, diff)
    end

    test "cleans science results with different values" do
      a = {
        @repo1 => { policy_a: :unsatisfied },
        @repo2 => { policy_a: :satisfied },
      }
      b = {
        @repo2 => { policy_a: :unsatisfied },
        @repo3 => { policy_a: :unsatisfied },
      }
      a_diff_b = ::ConditionalAccess::Filter.clean_science_result(a, b)
      b_diff_a = ::ConditionalAccess::Filter.clean_science_result(b, a)

      assert_same_hash({
        { type: "Repository", id: @repo1.id, } => { policy_a: :unsatisfied },
        { type: "Repository", id: @repo2.id, } => { policy_a: :satisfied },
      }, a_diff_b)

      assert_same_hash({
        { type: "Repository", id: @repo2.id, } => { policy_a: :unsatisfied },
        { type: "Repository", id: @repo3.id, } => { policy_a: :unsatisfied },
      }, b_diff_a)
    end
  end

  test "unauthorized shortcuts work" do
    assert_kind_of ConditionalAccess::ResultSet, @filter.unauthorized(Repository.all)
    assert_same_elements [@repo2, @repo3], @filter.unauthorized(Repository.all).resources
    assert_same_elements [@repo2, @repo3], @filter.unauthorized_resources(Repository.all)
    assert_same_elements [@repo2.id, @repo3.id], @filter.unauthorized_resource_ids(Repository.all)
  end

  test "authorized shortcuts work" do
    assert_kind_of ConditionalAccess::ResultSet, @filter.authorized(Repository.all)
    assert_same_elements [@repo1], @filter.authorized(Repository.all).resources
    assert_same_elements [@repo1], @filter.authorized_resources(Repository.all)
    assert_same_elements [@repo1.id], @filter.authorized_resource_ids(Repository.all)
  end

  test "satisfied shortcut works" do
    assert_empty @filter.satisfied_resources(Repository.all)
    assert_same_elements [@repo1, @repo3], @filter.satisfied_resources(Repository.all, only: :membership)
    assert_same_elements [@repo1, @repo2], @filter.satisfied_resources(Repository.all, only: :first_letter_a)
    assert_same_elements [@repo1], @filter.satisfied_resources(Repository.all, only: [:first_letter_a, :membership])
  end

  context "perform_filter" do
    test "invokes perform_filter" do
      @filter.stubs(:conditional_access_policies).returns([:random])
      @filter.expects(:perform_filter).at_least_once
      result = @filter.evaluate(all_repos_sorted)
    end

    test "invokes multiple_applicable on callback if it exists" do
      @filter.expects(:multiple_notapplicable_applicable).with(all_repos_sorted.map { |r| r.owner }, instance_of(ConditionalAccess::TargetProvider)).returns([]).at_least_once
      @filter.unauthorized(all_repos_sorted)
    end

    test "returns inapplicable results not returned by multiple_applicable" do
      @filter.stubs(:conditional_access_policies).returns([:random])
      @filter.expects(:multiple_random_applicable).with(all_repos_sorted.map { |r| r.owner }, instance_of(ConditionalAccess::TargetProvider)).returns([Repository.first.owner]).at_least_once
      result = @filter.evaluate(all_repos_sorted)
      assert_equal result[Repository.first].policies, { random: { private: :unsatisfied } }
      assert_equal result[Repository.second].policies, { random: { private: :inapplicable } }
      assert_equal result[Repository.third].policies, { random: { private: :inapplicable } }
    end

    test "does not invoke multiple_applicable on callback if it does not exist - and every target is considered applicable" do
      @filter.stubs(:conditional_access_policies).returns([:random])
      @filter.expects(:multiple_random_satisfied).with(all_repos_sorted.map { |r| r.owner }, instance_of(ConditionalAccess::TargetProvider)).returns({}).at_least_once
      @filter.unauthorized(all_repos_sorted)
    end

    test "invokes multiple_satisfied on callback if it exists" do
      @filter.stubs(:conditional_access_policies).returns([:random])
      @filter.expects(:multiple_random_satisfied).with(all_repos_sorted.map { |r| r.owner }, instance_of(ConditionalAccess::TargetProvider)).returns({}).at_least_once
      @filter.unauthorized(all_repos_sorted)
    end

    test "returns satisfied if returned by multiple_satisfied, unsatisfied otherwise" do
      @filter.stubs(:conditional_access_policies).returns([:random])
      @filter.expects(:multiple_random_satisfied).with(all_repos_sorted.map { |r| r.owner }, instance_of(ConditionalAccess::TargetProvider)).returns({ Repository.first.owner => { private: :satisfied } }).at_least_once

      result = @filter.evaluate(all_repos_sorted)
      assert_equal result[Repository.first].policies, { random: { private: :satisfied } }
      assert_equal result[Repository.second].policies, { random: { private: :unsatisfied } }
      assert_equal result[Repository.third].policies, { random: { private: :unsatisfied } }
    end

    test "does not invoke multiple_satisfied on callback if it does not exist - and every target is considered unsatisfied" do
      @filter.stubs(:conditional_access_policies).returns([:random])
      result = @filter.unauthorized(Repository.all)
      assert_same_elements Repository.all.to_a, result.resources
    end

    test "invokes policy methods grouped by TFCA class" do
      business = create(:business)
      user_owned_repo = create(:repository)
      @filter.stubs(:conditional_access_policies).returns([:random])
      @filter.expects(:multiple_random_satisfied).with([Repository.first.owner], instance_of(ConditionalAccess::TargetProvider)).returns({}).at_least_once
      @filter.expects(:multiple_random_satisfied).with([business], instance_of(ConditionalAccess::TargetProvider)).returns({}).at_least_once
      @filter.expects(:multiple_random_satisfied).with([user_owned_repo.owner], instance_of(ConditionalAccess::TargetProvider)).returns({}).at_least_once
      @filter.unauthorized([Repository.first, business, user_owned_repo])
    end

    test "does not invoke multiple_satisfied if there are no applicable resources" do
      @filter.expects(:multiple_notapplicable_applicable).with(all_repos_sorted.map { |r| r.owner }, instance_of(ConditionalAccess::TargetProvider)).returns([]).at_least_once
      @filter.expects(:multiple_notapplicable_satisfied).never
      @filter.unauthorized(all_repos_sorted)
    end

    test "prefill only expected values" do
      queries = [
        "SELECT internal_repositories.* FROM internal_repositories WHERE internal_repositories.repository_id IN ?", # prefill internal_repository of to resduce risk of N+1 when evaluating the visibility
        "SELECT business_organization_memberships.* FROM business_organization_memberships WHERE business_organization_memberships.organization_id IN ?", # prefill the business for orgs, to reduce risk of N+1 when accessing the business of an target
        "SELECT users.* FROM users WHERE users.id IN ?" # prefill owners of repositories in multiple_target_for_conditional_access
      ]
      resources = Repository.all.to_a
      result = assert_sql_queries(queries) do
        @filter.authorized_resources(resources, only: :first_letter_a)
      end
      assert_same_elements [@repo1, @repo2], result
    end
  end

  test "doesn't prefill already loaded associations" do
    @repo1.owner.business
    @repo2.owner.business
    @repo3.owner.business
    @repo1.internal_repository
    @repo2.internal_repository
    @repo3.internal_repository

    resources = [@repo1, @repo2, @repo3]

    result = assert_sql_queries([]) do
      @filter.authorized_resources(resources, only: :first_letter_a)
    end
    assert_same_elements [@repo1, @repo2], result
  end

  context "safe_multiple_targets_for_conditional_access" do
    test "raises if something other than an enumerable is passed" do
      assert_raises ConditionalAccess::Filter::Error do
        @filter.send(:safe_multiple_targets_for_conditional_access, Repository.first)
      end
    end

    test "raises if resource does not implement multiple_target_for_conditional_access" do
      assert_raises ConditionalAccess::Filter::Error do
        @filter.send(:safe_multiple_targets_for_conditional_access, [Object.new, Object.new])
      end
    end

    test "dispatches to the classes corresponding method multiple_target_for_conditional_access method" do
      enumerable = Repository.all.to_a
      results = Repository.multiple_target_for_conditional_access(enumerable)
      Repository.expects(:multiple_target_for_conditional_access).with(enumerable).returns(results).at_least_once
      @filter.send(:safe_multiple_targets_for_conditional_access, enumerable)
    end

    test "caches results per resource" do
      Repository.expects(:multiple_target_for_conditional_access).with([@repo1, @repo2]).returns({ @repo1 => @org1, @repo2 => @org2 }).once
      Repository.expects(:multiple_target_for_conditional_access).with([@repo3]).returns({ @repo3 => @org3 }).once
      assert_equal Hash[@repo1, @org1, @repo2, @org2],
                   @filter.send(:safe_multiple_targets_for_conditional_access, [@repo1, @repo2])
      assert_equal Hash[@repo1, @org1, @repo2, @org2, @repo3, @org3],
                   @filter.send(:safe_multiple_targets_for_conditional_access, [@repo1, @repo2, @repo3])
    end

    test "maintains input order" do
      repo1 = create(:repository)
      org1 = create(:organization)
      user = create(:user)
      repo2 = create(:repository)
      org2 = create(:organization)
      resources = [repo1, org1, user, repo2, org2]
      expected = { repo1 => repo1.owner, org1 => org1, user => user, repo2 => repo2.owner, org2 => org2 }
      result = @filter.send(:safe_multiple_targets_for_conditional_access, resources)
      assert_equal expected, result
    end

    test "raises if any resource's targets_for_conditional_access is `nil`" do
      repo1 = create(:repository)
      resources = [repo1]
      Repository.expects(:multiple_target_for_conditional_access).with(resources).returns({ repo1 => nil })

      assert_raises_with_message ConditionalAccess::Filter::Error, "Repository#multiple_target_for_conditional_access returned a nil value. nil is not a valid target for conditional access, only User/Organization/Business are allowed" do
        @filter.send(:safe_multiple_targets_for_conditional_access, resources)
      end
    end

    test "raises if returned resources do not match passed resources" do
      org1 = create(:organization)
      org2 = create(:organization)
      resources = [org1, org2]
      missing_resource_response = { org2 => org2 }
      Organization.expects(:multiple_target_for_conditional_access).with(resources).returns(missing_resource_response)

      assert_raises_with_message ConditionalAccess::Filter::Error, "could not determine target for conditional access for #{org1.class.name} #{org1.id}" do
        @filter.send(:safe_multiple_targets_for_conditional_access, resources)
      end
    end
  end
end
