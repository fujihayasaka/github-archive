# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Risk
    class SortByTest < GitHub::TestCase
      fixtures do
        now = Time.now

        @org = create(:organization)
        @page_size = 25

        @repo1 = create(:repository, name: "repo-a", owner: @org, pushed_at: now - 2.days)
        @repo1_config = create(:repository_security_center_config, repository: @repo1, ghas_enabled: true)
        @repo1_dbot_status = create(:repository_security_center_status, repository: @repo1, feature_type: "dependabot_alerts", scanning_status: "enrolled", scanning_count: 1)
        @repo1_cs_status = create(:repository_security_center_status, repository: @repo1, feature_type: "code_scanning", scanning_status: "enrolled", scanning_count: 2)
        @repo1_ss_status = create(:repository_security_center_status, repository: @repo1, feature_type: "secret_scanning", scanning_status: "enrolled", scanning_count: 3)

        @repo2 = create(:repository, name: "repo-b", owner: @org, pushed_at: now - 1.day)
        @repo2_config = create(:repository_security_center_config, repository: @repo2, ghas_enabled: true)
        @repo2_dbot_status = create(:repository_security_center_status, repository: @repo2, feature_type: "dependabot_alerts", scanning_status: "enrolled", scanning_count: 3)
        @repo2_cs_status = create(:repository_security_center_status, repository: @repo2, feature_type: "code_scanning", scanning_status: "enrolled", scanning_count: 3)
        @repo2_ss_status = create(:repository_security_center_status, repository: @repo2, feature_type: "secret_scanning", scanning_status: "enrolled", scanning_count: 1)

        @repo3 = create(:repository, name: "repo-c", owner: @org, pushed_at: now)
        @repo3_config = create(:repository_security_center_config, repository: @repo3, ghas_enabled: true)
        @repo3_dbot_status = create(:repository_security_center_status, repository: @repo3, feature_type: "dependabot_alerts", scanning_status: "enrolled", scanning_count: 2)
        @repo3_cs_status = create(:repository_security_center_status, repository: @repo3, feature_type: "code_scanning", scanning_status: "enrolled", scanning_count: 1)
        @repo3_ss_status = create(:repository_security_center_status, repository: @repo3, feature_type: "secret_scanning", scanning_status: "enrolled", scanning_count: 2)
      end

      context "#apply" do
        test "orders by repository last_push desc by default" do
          rel_with_sort = SortBy.new(
            nil,
            organizations: [@org],
            page_size: @page_size
          ).apply(
            RepositorySecurityCenterConfig.all,
            page: 1
          )
          assert_equal [@repo3_config, @repo2_config, @repo1_config].map(&:name), rel_with_sort.map(&:name)

          expected_clause = Arel.sql("`#{RepositorySecurityCenterConfig.table_name}`.`last_push` DESC, `#{RepositorySecurityCenterConfig.table_name}`.`name` ASC")
          assert rel_with_sort.to_sql.include?(expected_clause)
        end

        test "orders by repository last_push desc by default if option is not supported" do
          rel_with_sort = SortBy.new(
            "woooooof",
            organizations: [@org],
            page_size: @page_size
          ).apply(
            RepositorySecurityCenterConfig.all,
            page: 1
          )
          assert_equal [@repo3_config, @repo2_config, @repo1_config].map(&:name), rel_with_sort.map(&:name)

          expected_clause = Arel.sql("`#{RepositorySecurityCenterConfig.table_name}`.`last_push` DESC, `#{RepositorySecurityCenterConfig.table_name}`.`name` ASC")
          assert rel_with_sort.to_sql.include?(expected_clause)
        end

        test "orders by repository last_push desc if option set to last-updated" do
          rel_with_sort = SortBy.new(
            "last-updated",
            organizations: [@org],
            page_size: @page_size
          ).apply(
            RepositorySecurityCenterConfig.all,
            page: 1
          )
          assert_equal [@repo3_config, @repo2_config, @repo1_config].map(&:name), rel_with_sort.map(&:name)
        end

        test "orders by repository name asc if option set to repos" do
          rel_with_sort = SortBy.new(
            "repos",
            organizations: [@org],
            page_size: @page_size
          ).apply(
            RepositorySecurityCenterConfig.all,
            page: 1
          )
          assert_equal [@repo1_config, @repo2_config, @repo3_config].map(&:name), rel_with_sort.map(&:name)
        end

        test "orders by dependabot alerts count desc if option set to dependabot" do
          rel_with_sort = SortBy.new(
            "dependabot",
            organizations: [@org],
            page_size: @page_size
          ).apply(
            RepositorySecurityCenterConfig.all,
            page: 1
          )
          assert_equal [@repo2_config, @repo3_config, @repo1_config].map(&:name), rel_with_sort.map(&:name)
        end

        test "orders by code scanning alerts count desc if option set to secret-scanning" do
          rel_with_sort = SortBy.new(
            "code-scanning",
            organizations: [@org],
            page_size: @page_size
          ).apply(
            RepositorySecurityCenterConfig.all,
            page: 1
          )
          assert_equal [@repo2_config, @repo1_config, @repo3_config].map(&:name), rel_with_sort.map(&:name)
        end

        test "orders by secret scanning alerts count desc if option set to secret-scanning" do
          rel_with_sort = SortBy.new(
            "secret-scanning",
            organizations: [@org],
            page_size: @page_size
          ).apply(
            RepositorySecurityCenterConfig.all,
            page: 1
          )
          assert_equal [@repo1_config, @repo3_config, @repo2_config].map(&:name), rel_with_sort.map(&:name)
        end
      end
    end
  end
end
