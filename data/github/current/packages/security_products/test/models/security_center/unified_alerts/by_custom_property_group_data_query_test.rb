# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class ByCustomPropertyGroupDataQueryTest < GitHub::TestCase
      extend T::Sig
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)
        @repo = create(:private_repository, owner: @org)

        @custom_property_string = create(
          :custom_property_definition,
          :string,
          source: @org,
          property_name: "test-string-property"
        )
        @repo = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo, enabled_features: [SecurityFeatures::SECRET_SCANNING])
        create(:custom_property_value, target: @repo, definition: @custom_property_string, value: "string value")

        @custom_property_multi_select = create(
          :custom_property_definition,
          :multi_select,
          source: @org,
          property_name: "test-multi-select-property",
          allowed_values: %w[value1 value2 value3 value4]
        )
        repo_value1_value2 = create(:internal_repository, owner: @org)
        create_repo_alerts(repository: repo_value1_value2)
        create(:custom_property_value, target: repo_value1_value2, definition: @custom_property_multi_select, value: "value1")
        create(:custom_property_value, target: repo_value1_value2, definition: @custom_property_multi_select, value: "value2")
        repo_value2 = create(:internal_repository, owner: @org)
        create_repo_alerts(repository: repo_value2, enabled_features: [SecurityFeatures::SECRET_SCANNING])
        create(:custom_property_value, target: repo_value2, definition: @custom_property_multi_select, value: "value2")
        repo_value3 = create(:internal_repository, owner: @org)
        create_repo_alerts(repository: repo_value3, enabled_features: [SecurityFeatures::SECRET_SCANNING])
        create(:custom_property_value, target: repo_value3, definition: @custom_property_multi_select, value: "value3")
        repo_value4 = create(:internal_repository, owner: @org)
        create_repo_alerts(repository: repo_value4, no_alert_data: true)
        create(:custom_property_value, target: repo_value4, definition: @custom_property_multi_select, value: "value4")

        # repo from another org
        another_org = create(:organization, business: @biz, admin: @org_admin)
        another_org_definition = create(
          :custom_property_definition,
          :multi_select,
          source: another_org,
          property_name: @custom_property_multi_select.property_name,
          allowed_values: %w[value1 value2 value3 value4]
        )
        # 2 critical, 1 medium, 1 informational
        another_org_repo_value1 = create(:internal_repository, owner: @org)
        create_repo_alerts(repository: another_org_repo_value1, enabled_features: [SecurityFeatures::SECRET_SCANNING])
        create(:custom_property_value, target: another_org_repo_value1, definition: another_org_definition, value: "value1")
      end

      setup do
        SecurityFeatures.stubs(:visible_features).returns([
          SecurityFeatures::SECRET_SCANNING ,
          SecurityFeatures::CODE_SCANNING,
          SecurityFeatures::DEPENDABOT_ALERTS,
        ])
        @query = ::Search::Queries::SecurityCenter::QueryParser.new("is:open archived:false")
      end

      test "raises ArgumentError if cursor value is invalid" do
        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("repo.props.#{@custom_property_multi_select.property_name}", cursor: "-1")
        end

        assert_raises ArgumentError do
          GroupDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run("repo.props.#{@custom_property_multi_select.property_name}", cursor: "test")
        end
      end

      test "returns list of groups" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("repo.props.#{@custom_property_multi_select.property_name}", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 4, alert_groups.count

        assert_equal "repo.props.#{@custom_property_multi_select.property_name}:value2", T.must(alert_groups[0])[:key]
        assert_equal "value2", T.must(alert_groups[0])[:name]
        assert_equal 4, T.must(alert_groups[0])[:count_critical]
        assert_equal 2, T.must(alert_groups[0])[:count_high]
        assert_equal 2, T.must(alert_groups[0])[:count_medium]
        assert_equal 2, T.must(alert_groups[0])[:count_low]
        assert_equal 11, T.must(alert_groups[0])[:total]

        assert_equal "repo.props.#{@custom_property_multi_select.property_name}:value1", T.must(alert_groups[1])[:key]
        assert_equal "value1", T.must(alert_groups[1])[:name]
        assert_equal 3, T.must(alert_groups[1])[:count_critical]
        assert_equal 2, T.must(alert_groups[1])[:count_high]
        assert_equal 2, T.must(alert_groups[1])[:count_medium]
        assert_equal 2, T.must(alert_groups[1])[:count_low]
        assert_equal 10, T.must(alert_groups[1])[:total]

        assert_equal "repo.props.#{@custom_property_multi_select.property_name}:value3", T.must(alert_groups[2])[:key]
        assert_equal "value3", T.must(alert_groups[2])[:name]
        assert_equal 1, T.must(alert_groups[2])[:count_critical]
        assert_equal 0, T.must(alert_groups[2])[:count_high]
        assert_equal 0, T.must(alert_groups[2])[:count_medium]
        assert_equal 0, T.must(alert_groups[2])[:count_low]
        assert_equal 1, T.must(alert_groups[2])[:total]

        assert_equal "repo.props.#{@custom_property_multi_select.property_name}:value4", T.must(alert_groups[3])[:key]
        assert_equal "value4", T.must(alert_groups[3])[:name]
        assert_equal 0, T.must(alert_groups[3])[:count_critical]
        assert_equal 0, T.must(alert_groups[3])[:count_high]
        assert_equal 0, T.must(alert_groups[3])[:count_medium]
        assert_equal 0, T.must(alert_groups[3])[:count_low]
        assert_equal 0, T.must(alert_groups[3])[:total]
      end

      test "supports paging and contains next cursor" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("repo.props.#{@custom_property_multi_select.property_name}", cursor: "1", page_size: 2)
        assert_equal "0", result.previous
        assert_equal "3", result.next

        alert_groups = result.alert_groups
        assert_equal 2, alert_groups.count

        assert_equal "repo.props.#{@custom_property_multi_select.property_name}:value1", T.must(alert_groups[0])[:key]
        assert_equal "value1", T.must(alert_groups[0])[:name]
        assert_equal 3, T.must(alert_groups[0])[:count_critical]
        assert_equal 2, T.must(alert_groups[0])[:count_high]
        assert_equal 2, T.must(alert_groups[0])[:count_medium]
        assert_equal 2, T.must(alert_groups[0])[:count_low]
        assert_equal 10, T.must(alert_groups[0])[:total]

        assert_equal "repo.props.#{@custom_property_multi_select.property_name}:value3", T.must(alert_groups[1])[:key]
        assert_equal "value3", T.must(alert_groups[1])[:name]
        assert_equal 1, T.must(alert_groups[1])[:count_critical]
        assert_equal 0, T.must(alert_groups[1])[:count_high]
        assert_equal 0, T.must(alert_groups[1])[:count_medium]
        assert_equal 0, T.must(alert_groups[1])[:count_low]
        assert_equal 1, T.must(alert_groups[1])[:total]
      end

      test "returns nothing if property is string type" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("repo.props.#{@custom_property_string.property_name}", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 0, alert_groups.count
      end

      test "returns nothing if property not found" do
        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("repo.props.test-unknown-property", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 0, alert_groups.count
      end

      test "returns nothing if property has no repositories mapping" do
        test_property = create(
          :custom_property_definition,
          :multi_select,
          source: @org,
          property_name: "test-property-without-repo-mapping",
          allowed_values: %w[value1 value2 value3 value4]
        )

        result = GroupDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run("repo.props.#{test_property.property_name}", cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alert_groups = result.alert_groups
        assert_equal 0, alert_groups.count
      end
    end
  end
end
