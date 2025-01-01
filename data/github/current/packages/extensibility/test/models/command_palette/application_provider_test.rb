# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class ApplicationProviderTest < GitHub::TestCase
    include ConditionalAccess::FilterTestHelper
    include GitHub::CommandPaletteTestHelpers

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @user = create(:user, :verified)
      @context = build_context(current_user: @user)

      @inaccessible_org = create(:business_plus_org, name: "inaccessible")
      @accessible_org = create(:business_plus_org, name: "accessible")
      inaccessible_org_results = build_results(@inaccessible_org)
      @accessible_org_results = build_results(@accessible_org)
      @no_object_result = build_result(title: "no object result")

      @all_results = inaccessible_org_results + @accessible_org_results + [@no_object_result]
    end

    test "has a factory_identifier" do
      expected = :application
      assert_equal expected, ApplicationProvider.factory_identifier
    end

    test "element configuration" do
      assert_equal [:default], ApplicationProvider.send(:modes)
      assert_equal "remote", ApplicationProvider.type
      assert_equal 200, ApplicationProvider.debounce
    end

    test "has a context" do
      abstract_provider = ApplicationProvider.new(@context)
      refute_nil abstract_provider.context
    end

    test "delegates #current_user to context" do
      abstract_provider = ApplicationProvider.new(@context)
      refute_nil abstract_provider.current_user
    end

    test "defaults .enabled? to true" do
      assert ApplicationProvider.enabled?(@context)
    end

    test "responds to #search" do
      abstract_provider = ApplicationProvider.new(@context)
      assert abstract_provider.respond_to?(:search)
    end

    test "raises when #search is invoked" do
      abstract_provider = ApplicationProvider.new(@context)
      assert_raises NotImplementedError do
        abstract_provider.search(nil)
      end
    end

    context "filter_results" do
      test "returns unfiltered results if cap_filter is nil" do
        context_without_cap_filter = build_context(current_user: @user, scope: @inaccessible_org, no_cap_filter: true)
        provider = ApplicationProvider.new(context_without_cap_filter)

        provider.expects(:filtered_by_unauthorized_policies).never
        filtered_results = provider.filter_results(@all_results)
        assert_same_elements @all_results.map(&:title), filtered_results.map(&:title)
      end

      test "returns filtered results when there are applicable unauthorized CAP policies" do
        context_with_cap_policies = build_context(current_user: @user, cap_filter: cap_unauthorizing_filter([@inaccessible_org]))

        expected_results = @accessible_org_results.dup
        # Add expected access policy results
        context_with_cap_policies.cap_filter.conditional_access_policies.each do |policy|
          expected_results << Result.access_policy(policy, @inaccessible_org, "/")
        end
        expected_results << @no_object_result

        provider = ApplicationProvider.new(context_with_cap_policies)
        filtered_results = provider.filter_results(@all_results)

        assert_same_elements expected_results.map(&:title), filtered_results.map(&:title)
      end

      test "returns filtered results when there are no applicable unauthorized CAP policies" do
        context_with_cap_policies = build_context(current_user: @user, cap_filter: cap_authorizing_filter([@inaccessible_org, @accessible_org]))
        provider = ApplicationProvider.new(context_with_cap_policies)
        filtered_results = provider.filter_results(@all_results)

        assert_same_elements @all_results.map(&:title), filtered_results.map(&:title)
      end
    end

    context "#query_matches_allowed_types?" do
      test "true only when exact match" do
        provider = ApplicationProvider.new(nil)

        refute provider.query_matches_allowed_types?("project", query: "is:projec")
        assert provider.query_matches_allowed_types?("project", query: "is:project")
        refute provider.query_matches_allowed_types?("project", query: "is:projects")
      end

      test "true when empty or not present" do
        provider = ApplicationProvider.new(nil)

        assert provider.query_matches_allowed_types?("project", query: "")
        assert provider.query_matches_allowed_types?("project", query: "is:")
      end

      test "true for any of the allowed types" do
        provider = ApplicationProvider.new(nil)
        types = %w[pr merged unmerged]

        types.each do |type|
          assert provider.query_matches_allowed_types?(*types, query: "is:#{type}")
        end
      end

      test "true when multiple values are all in allowed types" do
        provider = ApplicationProvider.new(nil)
        types = %w[pr merged unmerged]

        assert provider.query_matches_allowed_types?(*types, query: "is:pr foo is:merged bar is:unmerged")
        refute provider.query_matches_allowed_types?(*types, query: "is:pr foo is:merged bar is:not_valid")
      end

      test "can look at different filter name" do
        provider = ApplicationProvider.new(nil)

        assert provider.query_matches_allowed_types?("frank", query: "name:frank", filter: :name)
        refute provider.query_matches_allowed_types?("frank", query: "name:claire", filter: :name)
      end
    end

    def build_results(org)
      repo = create(:repository, owner: org, has_discussions: true)
      issue = create(:issue, repository: repo, title: "#{org.name} issue")
      discussion = create(:discussion, user: @user, repository: repo, title: "#{org.name} org repo discussion 1")

      [
        build_result(object: org, title: "#{org.name} org result", group: :organizations),
        build_result(object: repo, title: "#{org.name} repo result", group: :repositories),
        build_result(object: issue, title: "#{org.name} issue result", group: :references),
        build_result(object: discussion, title: "#{org.name} discussion result", group: :references)
      ]
    end
  end
end
