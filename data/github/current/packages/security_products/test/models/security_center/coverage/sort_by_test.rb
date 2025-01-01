# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Coverage
    class SortByTest < GitHub::TestCase
      fixtures do
        now = Time.now

        @org = create(:organization)

        @repo1 = create(:repository, name: "repo-a", owner: @org, pushed_at: now - 1.day)
        @repo1_config = create(:repository_security_center_config, repository: @repo1, ghas_enabled: true)

        @repo2 = create(:repository, name: "repo-b", owner: @org, pushed_at: now)
        @repo2_config = create(:repository_security_center_config, repository: @repo2, ghas_enabled: true)
      end

      context "#apply" do
        test "orders by repository last_push desc by default" do
          rel_with_sort = SortBy.new(nil).apply(RepositorySecurityCenterConfig.all)
          assert_equal [@repo2_config, @repo1_config].map(&:name), rel_with_sort.map(&:name)
          expected_clause = Arel.sql("`#{RepositorySecurityCenterConfig.table_name}`.`last_push` DESC, `#{RepositorySecurityCenterConfig.table_name}`.`name` ASC")
          assert rel_with_sort.to_sql.include?(expected_clause)
        end

        test "orders by repository last_push desc by default if option is not supported" do
          rel_with_sort = SortBy.new("woooooof").apply(RepositorySecurityCenterConfig.all)
          assert_equal [@repo2_config, @repo1_config].map(&:name), rel_with_sort.map(&:name)
          expected_clause = Arel.sql("`#{RepositorySecurityCenterConfig.table_name}`.`last_push` DESC, `#{RepositorySecurityCenterConfig.table_name}`.`name` ASC")
          assert rel_with_sort.to_sql.include?(expected_clause)
        end

        test "orders by repository last_push desc if option set to last-updated" do
          rel_with_sort = SortBy.new("last-updated").apply(RepositorySecurityCenterConfig.all)
          assert_equal [@repo2_config, @repo1_config].map(&:name), rel_with_sort.map(&:name)
        end

        test "orders by repository name asc if option set to repos" do
          rel_with_sort = SortBy.new("repos").apply(RepositorySecurityCenterConfig.all)
          assert_equal [@repo1_config, @repo2_config].map(&:name), rel_with_sort.map(&:name)
        end
      end
    end
  end
end
