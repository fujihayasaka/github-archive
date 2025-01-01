# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  module Filters
    class AdvancedFiltersTest < GitHub::TestCase
      fixtures do
        business = create(:global_business)
        @user = create(:user)
        @org = create(:organization, business: business, admin: @user)
        @team = create(:team, organization: @org, name: "test-team")

        @repo1 = create(:repository, owner: @org)
        @repo2 = create(:private_repository, owner: @org)
        @repo3 = create(:internal_repository, owner: @org)
        @repo4 = create(:repository, owner: @org)

        create_repo_security_center_config(repository: @repo1, ghas_enabled: false)
        create_repo_security_center_config(repository: @repo2, ghas_enabled: true, features: { secret_scanning: "not_enrolled" })
        create_repo_security_center_config(repository: @repo3, ghas_enabled: true, features: { secret_scanning: "not_enrolled" })
        create_repo_security_center_config(repository: @repo4, ghas_enabled: false)
      end

      def create_repo_security_center_config(repository:, ghas_enabled: true, features: {})
        create(:repository_security_center_config, repository:, ghas_enabled:)

        features.each do |feature, scanning_status|
          create(:repository_security_center_status, feature, scanning_status:, repository:)
        end
      end

      context "#apply" do
        test "returns repos matching the search query" do
          search_query = "advanced-security:enabled secret-scanning-alerts:disabled"
          filter = SecurityProductsEnablement::Filters::AdvancedFilters.new(
            @user,
            @org,
            Search::Queries::SecurityConfigurations::RepositoryQuery.new(query: search_query).mysql_query_hash
          )

          repo_ids = filter.apply
          assert_equal Set.new([@repo3.id, @repo2.id]), repo_ids
        end
      end
    end
  end
end
