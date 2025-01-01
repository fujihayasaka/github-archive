# typed: false
# frozen_string_literal: true

require "test_helper"

class ConditionalAccessResultSetTest < GitHub::TestCase
  setup do
    @results = ConditionalAccess::ResultSet::new [
      ConditionalAccess::Result::new(:resource1, Hash[:saml, :inapplicable, :ip_allowlist, :inapplicable, :other, :satisfied]),
      ConditionalAccess::Result::new(:resource2, Hash[:saml, :unsatisfied, :ip_allowlist, :inapplicable, :other, :inapplicable]),
      ConditionalAccess::Result::new(:resource3, Hash[:saml, :satisfied, :ip_allowlist, :unsatisfied, :other, :inapplicable]),
      ConditionalAccess::Result::new(:resource4, Hash[:saml, :satisfied, :ip_allowlist, :satisfied, :other, :inapplicable]),
      ConditionalAccess::Result::new(:resource5, Hash[:saml, :unsatisfied, :ip_allowlist, :satisfied, :other, :inapplicable]),
      ConditionalAccess::Result::new(:resource6, Hash[:saml, :unsatisfied, :ip_allowlist, :unsatisfied, :other, :inapplicable]),
      ConditionalAccess::Result::new(:resource7, Hash[:saml, :inapplicable, :ip_allowlist, :unsatisfied, :other, :inapplicable]),
      ConditionalAccess::Result::new(:resource8, Hash[:saml, :unenforceable, :ip_allowlist, :unsatisfied, :other, :inapplicable]),
    ]
  end

  test "resources returns Array of original resources provided" do
    results = ConditionalAccess::ResultSet::new [
      ConditionalAccess::Result::new(:resource1, Hash[:foo, :satisfied]),
      ConditionalAccess::Result::new(:resource2, Hash[:foo, :satisfied]),
      ConditionalAccess::Result::new(:resource3, Hash[:foo, :satisfied]),
    ]
    assert_equal [:resource1, :resource2, :resource3], results.resources
  end

  context "authorized" do
    test "raises if given nil parameter" do
      assert_raises ArgumentError do
        @results.authorized(nil)
      end
    end

    test "returns resources with no unsatisfied policies if no policies specified" do
      filtered = @results.authorized
      assert_equal [:resource1, :resource4], filtered.resources

      # Also removes the unsatisfied policies from the result set entirely (there shouldn't be any but we'll check just in case)
      assert_equal Hash[:saml, :inapplicable, :ip_allowlist, :inapplicable, :other, :satisfied], filtered[:resource1].policies
      assert_equal Hash[:saml, :satisfied, :ip_allowlist, :satisfied, :other, :inapplicable], filtered[:resource4].policies
    end

    test "returns resources that did not fail the specified policy" do
      saml_filtered = @results.authorized(only: :saml)
      assert_equal [:resource1, :resource3, :resource4, :resource7, :resource8], saml_filtered.resources

      # Also removes the unrelated policies from the result set entirely
      assert_equal Hash[:saml, :inapplicable], saml_filtered[:resource1].policies
      assert_equal Hash[:saml, :satisfied], saml_filtered[:resource3].policies
      assert_equal Hash[:saml, :satisfied], saml_filtered[:resource4].policies
      assert_equal Hash[:saml, :inapplicable], saml_filtered[:resource7].policies
      assert_equal Hash[:saml, :unenforceable], saml_filtered[:resource8].policies
    end

    test "returns resources that did not fail any of the specified policies" do
      saml_ip_filtered = @results.authorized(only: [:saml, :ip_allowlist])
      assert_equal [:resource1, :resource4], saml_ip_filtered.resources

      # Also removes the unrelated policies from the result set entirely
      assert_equal Hash[:saml, :inapplicable, :ip_allowlist, :inapplicable], saml_ip_filtered[:resource1].policies
      assert_equal Hash[:saml, :satisfied, :ip_allowlist, :satisfied], saml_ip_filtered[:resource4].policies
    end
  end

  context "unauthorized" do
    test "raises if given nil parameter" do
      assert_raises ArgumentError do
        @results.unauthorized(nil)
      end
    end

    test "returns resources with at least one unsatisfied policy if no policies specified" do
      filtered = @results.unauthorized
      assert_equal [:resource2, :resource3, :resource5, :resource6, :resource7, :resource8], filtered.resources

      # Also removes any authorized policies from the results (for by_policy to work well)
      assert_equal Hash[:saml, :unsatisfied], filtered[:resource2].policies
      assert_equal Hash[:ip_allowlist, :unsatisfied], filtered[:resource3].policies
      assert_equal Hash[:saml, :unsatisfied], filtered[:resource5].policies
      assert_equal Hash[:saml, :unsatisfied, :ip_allowlist, :unsatisfied], filtered[:resource6].policies
      assert_equal Hash[:ip_allowlist, :unsatisfied], filtered[:resource7].policies
      assert_equal Hash[:ip_allowlist, :unsatisfied], filtered[:resource8].policies
    end

    test "returns resources that failed the specified policy" do
      saml_filtered = @results.unauthorized(only: :saml)
      assert_equal [:resource2, :resource5, :resource6], saml_filtered.resources

      # Also removes the unrelated policies from the result set entirely
      assert_equal Hash[:saml, :unsatisfied], saml_filtered[:resource2].policies
      assert_equal Hash[:saml, :unsatisfied], saml_filtered[:resource5].policies
      assert_equal Hash[:saml, :unsatisfied], saml_filtered[:resource6].policies
    end

    test "returns resources that failed at least one of the specified policies" do
      saml_ip_filtered = @results.unauthorized(only: [:saml, :ip_allowlist])
      assert_equal [:resource2, :resource3, :resource5, :resource6, :resource7, :resource8], saml_ip_filtered.resources

      # Also removes the unrelated or authorized policies from the result set entirely
      assert_equal Hash[:saml, :unsatisfied], saml_ip_filtered[:resource2].policies
      assert_equal Hash[:ip_allowlist, :unsatisfied], saml_ip_filtered[:resource3].policies
      assert_equal Hash[:saml, :unsatisfied], saml_ip_filtered[:resource5].policies
      assert_equal Hash[:saml, :unsatisfied, :ip_allowlist, :unsatisfied], saml_ip_filtered[:resource6].policies
      assert_equal Hash[:ip_allowlist, :unsatisfied], saml_ip_filtered[:resource7].policies
      assert_equal Hash[:ip_allowlist, :unsatisfied], saml_ip_filtered[:resource8].policies
    end
  end

  context "indexer" do
    test "returns nil on unknown resource" do
      assert_nil @results[:not_a_real_resource]
    end

    test "returns a Result with full policy details" do
      assert_kind_of ConditionalAccess::Result, @results[:resource4]
      assert_equal :resource4, @results[:resource4].resource
      assert_equal Hash[:saml, :satisfied, :ip_allowlist, :satisfied, :other, :inapplicable], @results[:resource4].policies
    end
  end

  context "by_policy" do
    test "raises if ResultSet is not filtered" do
      e = assert_raises ConditionalAccess::ResultSet::NotFilteredError do
        @results.by_policy
      end
      assert_equal "by_policy can only be called after the ResultSet has been filtered using #unauthorized or #authorized", e.message
    end

    test "unauthorized.by_policy returns hash of resources grouped by failed policy" do
      assert_equal Hash[
        :saml, [:resource2, :resource5, :resource6],
        :ip_allowlist, [:resource3, :resource6, :resource7, :resource8]
      ], @results.unauthorized.by_policy
    end

    test "authorized.by_policy returns hash of resources grouped by passing policy" do
      assert_equal Hash[
        :saml, [:resource1, :resource4],
        :ip_allowlist, [:resource1, :resource4],
        :other, [:resource1, :resource4]
      ], @results.authorized.by_policy
    end
  end
end
