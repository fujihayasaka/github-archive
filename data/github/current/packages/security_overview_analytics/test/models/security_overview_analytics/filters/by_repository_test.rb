# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByRepositoryTest < GitHub::TestCase
      fixtures do
        @org = create(:organization, name: "test-org")

        @repo_a = create_repo("#{@org}-repo-a", owner: @org)
        @repo_b = create_repo("#{@org}-repo-b", owner: @org)
        @repo_c = create_repo("#{@org}-repo-c", owner: @org)

        # Business
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @business = create(:global_business)

        # Orgs in business
        @org1 = create(:business_plus_org, business: @business, name: "org-1")
        @org2 = create(:business_plus_org, business: @business, name: "org-2")

        @repo1 = create_repo("my-repo", owner: @org1)
        @repo2 = create_repo("my-repo", owner: @org2)
        @repo3 = create_repo("another-thing", owner: @org2)

        @owner = create(:user, name: "#{@org}-owner").tap do |u|
          @org.add_admin(u)
          @org1.add_admin(u)
          @org2.add_admin(u)
        end

        unless GitHub.enterprise?
          @mt_biz = create(:business, :enterprise_managed, name: "enterprise-managed-business")
          @mt_user = create(:emu, business: @mt_biz)
          @mt_org = create(:organization, business: @mt_biz, admin: @mt_user, name: "test-mt-org")
          @mt_org_repo = create_repo("mt-repo-a", owner: @mt_org, private: true)
          @mt_repo_a = create_repo("mt-repo-a", owner: @mt_user, private: true)
          @mt_repo_b = create_repo("mt-repo-b", owner: @mt_user, private: true)
        end
      end

      setup do
        @base_org_rel = base_query(owner_id: @org.id)
        @base_biz_rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)
        @base_emu_biz_rel = base_query(owner_id: @mt_biz.organizations.map(&:id), business_id: @mt_biz.id) unless GitHub.enterprise?
      end

      context "#apply" do
        context "substring matching" do
          test "filters by partial repository name" do
            filter = ByRepository.new([], [], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

            filter = ByRepository.new(["unknown"], [], substring_match: true)
            assert_empty filter.apply(@base_org_rel).map(&:repository_id)

            filter = ByRepository.new([@repo_a.name], [], substring_match: true)
            expected_repos = [@repo_a]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

            filter = ByRepository.new(["repo-a"], [], substring_match: true)
            expected_repos = [@repo_a]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

            filter = ByRepository.new(["repo"], [], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

            filter = ByRepository.new([], ["unknown"], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

            filter = ByRepository.new([], [@repo_a.name], substring_match: true)
            expected_repos = [@repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

            filter = ByRepository.new([], ["repo-a"], substring_match: true)
            expected_repos = [@repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

            filter = ByRepository.new([], ["repo"], substring_match: true)
            assert_empty filter.apply(@base_org_rel).map(&:repository_id)
          end

          context "business scope" do
            test "filters by partial standalone repo or org name" do
              filter = ByRepository.new([], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["unknown"], [], substring_match: true, scope: @business)
              assert_empty filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([@repo3.name], [], substring_match: true, scope: @business)
              expected_repos = [@repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["my-repo"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["repo"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["org-2"], [], substring_match: true, scope: @business)
              expected_repos = [@repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(%w[repo thing], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["unknown"], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], [@repo3.name], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["repo"], substring_match: true, scope: @business)
              expected_repos = [@repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["org-2"], substring_match: true, scope: @business)
              expected_repos = [@repo1]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], %w[repo thing], substring_match: true, scope: @business)
              assert_empty filter.apply(@base_biz_rel).map(&:repository_id)
            end

            test "filters by partial repo name within org if NWO is provided" do
              filter = ByRepository.new(["#{@org1.name}/unknown"], [], substring_match: true, scope: @business)
              assert_empty filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org1.name}/another"], [], substring_match: true, scope: @business)
              assert_empty filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org2.name}/another"], [], substring_match: true, scope: @business)
              expected_repos = [@repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org1.name}/my-"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org1.name}/my-", "#{@org2.name}/another"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org2.name}/"], [], substring_match: true, scope: @business)
              expected_repos = [@repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org1.name}/unknown"], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org2.name}/another"], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org1.name}/my-"], substring_match: true, scope: @business)
              expected_repos = [@repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org1.name}/my-", "#{@org2.name}/another"], substring_match: true, scope: @business)
              expected_repos = [@repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)
            end

            test "filters by a combination of standalone repo names and NWOs" do
              filter = ByRepository.new(["#{@org2.name}/another", "my-repo"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["another", "#{@org1.name}/my-"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org1.name}/my-", "another"], substring_match: true, scope: @business)
              expected_repos = [@repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org2.name}/another", "repo"], substring_match: true, scope: @business)
              assert_empty filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["repo"], ["#{@org1.name}/my-"], substring_match: true, scope: @business)
              expected_repos = [@repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org2.name}/"], ["another"], substring_match: true, scope: @business)
              expected_repos = [@repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)
            end

            context "for emus" do
              test "filters by partial standalone repo or user name" do
                on_multi_tenant_enterprise do
                  filter = ByRepository.new([], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["unknown"], [], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([@mt_repo_b.name], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["mt-repo-a"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["repo-a"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([@mt_user.name], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["repo-b"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(%w[repo thing], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  # negations
                  filter = ByRepository.new([], ["unknown"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], [@mt_repo_b.name], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], ["repo-a"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], [@mt_user.name], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], %w[repo thing], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(@base_emu_biz_rel).map(&:repository_id)
                end
              end

              test "filters by partial repo name if NWO is provided" do
                on_multi_tenant_enterprise do
                  filter = ByRepository.new(["#{@mt_user.name}/unknown"], [], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_org.name}/unknown"], [], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_user.name}/mt-repo-b"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_user.name}/mt-"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_org.name}/mt-", "#{@mt_user.name}/mt-"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_user.name}/"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  # negations
                  filter = ByRepository.new([], ["#{@mt_user.name}/unknown"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], ["#{@mt_user.name}/mt-repo-b"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], ["#{@mt_org.name}/mt-"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], ["#{@mt_org.name}/mt-", "#{@mt_user.name}/mt-repo-b"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)
                end
              end

              test "filters by a combination of standalone repo names and NWOs" do
                on_multi_tenant_enterprise do
                  filter = ByRepository.new([@mt_repo_b.nwo, "mt-repo-a"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["repo-a", "#{@mt_org.name}/mt-"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  # negations
                  filter = ByRepository.new([], ["#{@mt_org.name}/mt-", "mt-repo-a"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], ["#{@mt_org.name}/mt-", "repo-a", "repo-b"], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new([], ["repo"], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["repo"], [@mt_repo_a.nwo, "mt-repo-b"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_user.name}/"], ["repo-a"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(@base_emu_biz_rel).map(&:repository_id)
                end
              end
            end

            context "on ghes", enterprise_only: true do
              test "filters by partial standalone user name" do
                ghes_repo_a, ghes_repo_b = create_ghes_user_repos

                filter = ByRepository.new([ghes_repo_a.name], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new(["ghes-repo"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new(["repo-a"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new(%w(ghes-repo thing), [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a, ghes_repo_b, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                # negations
                filter = ByRepository.new([], ["ghes-repo"], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new([], [ghes_repo_a.name], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new([], [@owner.name], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)
              end

              test "filters by partial repo name with NWOs" do
                ghes_repo_a, ghes_repo_b = create_ghes_user_repos

                filter = ByRepository.new(["#{@owner.name}/ghes-"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new(["#{@owner.name}/ghes-repo-a"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new(["#{@owner.name}/"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                # negations
                filter = ByRepository.new([], ["#{@owner.name}/"], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new([], ["#{@owner.name}/ghes-"], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)

                filter = ByRepository.new([], ["#{@owner.name}/ghes-repo-b"], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3, ghes_repo_a]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)
              end

              test "filters by a combination of standalone repo names and NWOs" do
                ghes_repo_a, ghes_repo_b = create_ghes_user_repos

                filter = ByRepository.new(["ghes-repo", "#{@org2.name}/another"], [], substring_match: true, scope: @business)
                expected_repos = [@repo3, ghes_repo_a, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(@base_biz_rel).map(&:repository_id)
              end
            end
          end
        end

        test "filters by repository name" do
          filter = ByRepository.new([], [])
          expected_repos = [@repo_a, @repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

          filter = ByRepository.new([@repo_a.name], [])
          expected_repos = [@repo_a]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

          filter = ByRepository.new([@repo_b.name], [])
          expected_repos = [@repo_b]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

          filter = ByRepository.new([], [@repo_a.name])
          expected_repos = [@repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

          filter = ByRepository.new([], [@repo_b.name])
          expected_repos = [@repo_a, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)

          filter = ByRepository.new(["unknown"], [])
          assert_empty filter.apply(@base_org_rel).map(&:repository_id)

          filter = ByRepository.new([], ["unknown"])
          expected_repos = [@repo_a, @repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(@base_org_rel).map(&:repository_id)
        end

        test "doesn't apply clause if no filters are provided" do
          expected_clause = @base_org_rel.to_sql

          filter = ByRepository.new([], [])
          assert_equal expected_clause, filter.apply(@base_org_rel).to_sql
        end

        test "applies where clause with positive filters" do
          prefix_sql = @base_org_rel.to_sql

          filter = ByRepository.new([@repo_a.name], [])
          expected_clause = "AND `soa_repositories`.`name` = '#{@repo_a.name}'"
          assert_equal expected_clause, filter.apply(@base_org_rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with negated filters" do
          prefix_sql = @base_org_rel.to_sql

          filter = ByRepository.new([], [@repo_a.name])
          expected_clause = "AND `soa_repositories`.`name` != '#{@repo_a.name}'"
          assert_equal expected_clause, filter.apply(@base_org_rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with positive filter for EMUs" do
          on_multi_tenant_enterprise do
            prefix_sql = @base_emu_biz_rel.to_sql

            filter = ByRepository.new([@mt_repo_a.name], [], scope: @mt_biz)
            expected_clause = "AND `soa_repositories`.`name` = '#{@mt_repo_a.name}'"
            assert_equal expected_clause, filter.apply(@base_emu_biz_rel).to_sql.delete_prefix(prefix_sql).strip
          end
        end

        test "applies where clause with negative filter for EMUs" do
          on_multi_tenant_enterprise do
            prefix_sql = @base_emu_biz_rel.to_sql

            filter = ByRepository.new([], [@mt_repo_a.name], scope: @mt_biz)
            expected_clause = "AND `soa_repositories`.`name` != '#{@mt_repo_a.name}'"
            assert_equal expected_clause, filter.apply(@base_emu_biz_rel).to_sql.delete_prefix(prefix_sql).strip
          end
        end

        test "filters by repo name across orgs" do
          filter = ByRepository.new(["my-repo"], [], scope: @business)
          expected_repos = [@repo1, @repo2]
          assert_same_elements expected_repos.map(&:name), filter.apply(@base_biz_rel).map(&:name)
        end

        test "filters by repo name across EMUs" do
          on_multi_tenant_enterprise do
            other_user = create(:emu, business: @mt_biz)
            other_mt_repo_a = create_repo("mt-repo-a", owner: other_user, private: true)

            filter = ByRepository.new(["mt-repo-a"], [], scope: @mt_biz)
            expected_repos = [@mt_org_repo, @mt_repo_a, other_mt_repo_a]
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_emu_biz_rel).map(&:name)
          end
        end

        test "filters by repo nwo within specified org" do
          filter = ByRepository.new(["#{@org1}/my-repo"], [], scope: @business)
          expected_repos = [@repo1]
          assert_same_elements expected_repos.map(&:name), filter.apply(@base_biz_rel).map(&:name)
        end

        test "filters by repo nwo within specific EMU" do
          on_multi_tenant_enterprise do
            prefix_sql = @base_emu_biz_rel.to_sql

            filter = ByRepository.new([@mt_repo_a.nwo], [], scope: @mt_biz)
            expected_clause = "AND (`soa_repositories`.`business_id` = #{@mt_biz.id} AND (`soa_repositories`.`owner_id` = #{@mt_org.id} OR `soa_repositories`.`owner_type` = 'USER') AND 1=0 OR `soa_repositories`.`owner_id` = #{@mt_user.id} AND `soa_repositories`.`name` = '#{@mt_repo_a.name}')"
            assert_equal expected_clause, filter.apply(@base_emu_biz_rel).to_sql.delete_prefix(prefix_sql).strip
          end
        end

        context "filters by repo NWO on GHES", enterprise_only: true do
          test "filter by repo name" do
            ghes_repo_a, ghes_repo_b = create_ghes_user_repos
            prefix_sql = @base_biz_rel.to_sql

            filter = ByRepository.new([ghes_repo_a.name], [], scope: @business)
            result = filter.apply(@base_biz_rel)
            expected_clause = "AND `soa_repositories`.`name` = '#{ghes_repo_a.name}'"
            assert_equal expected_clause, result.to_sql.delete_prefix(prefix_sql).strip

            expected_repos = [ghes_repo_a]
            assert_same_elements expected_repos.map(&:name), result.map(&:name)
          end

          test "filter by repo name with negation" do
            ghes_repo_a, ghes_repo_b = create_ghes_user_repos
            prefix_sql = @base_biz_rel.to_sql

            filter = ByRepository.new([], [ghes_repo_a.name], scope: @business)
            result = filter.apply(@base_biz_rel)
            expected_clause = "AND `soa_repositories`.`name` != '#{ghes_repo_a.name}'"
            assert_equal expected_clause, result.to_sql.delete_prefix(prefix_sql).strip

            expected_repos = [@repo1, @repo2, @repo3, ghes_repo_b]
            assert_same_elements expected_repos.map(&:name), result.map(&:name)
          end

          test "filter by repo nwo" do
            ghes_repo_a, ghes_repo_b = create_ghes_user_repos
            prefix_sql = @base_biz_rel.to_sql

            filter = ByRepository.new([ghes_repo_a.nwo], [], scope: @business)
            result = filter.apply(@base_biz_rel)

            expected_repos = [ghes_repo_a]
            assert_same_elements expected_repos.map(&:name), result.map(&:name)
          end

          test "returns no results for unknown user" do
            ghes_repo_a, ghes_repo_b = create_ghes_user_repos
            prefix_sql = @base_biz_rel.to_sql

            filter = ByRepository.new(["#{@owner.name}/jhghjb"], [], scope: @business)
            result = filter.apply(@base_biz_rel)

            expected_repos = []
            assert_same_elements expected_repos.map(&:name), result.map(&:name)
          end
        end

        test "returns no results for unknown org in a repo nwo filter" do
          filter = ByRepository.new(["unknown-org/my-repo"], [], scope: @business)
          assert_empty filter.apply(@base_biz_rel).map(&:name)
        end

        test "returns no results for unknown repo in a nwo filter" do
          filter = ByRepository.new(["#{@org1}/unknown-repo"], [], scope: @business)
          assert_empty filter.apply(@base_biz_rel).map(&:name)
        end

        test "returns no results for unknown EMU in a repo nwo filter" do
          on_multi_tenant_enterprise do
            filter = ByRepository.new(["unknown/#{@mt_repo_a.name}"], [], scope: @mt_biz)
            assert_empty filter.apply(@base_emu_biz_rel).map(&:name)
          end
        end

        test "returns no results for unknown EMU repo in a nwo filter" do
          on_multi_tenant_enterprise do
            filter = ByRepository.new(["#{@mt_user}/foobar"], [], scope: @mt_biz)
            assert_empty filter.apply(@base_emu_biz_rel).map(&:name)
          end
        end

        test "returns no results for invalid repo nwo filter" do
          filter = ByRepository.new(["/my-repo"], [], scope: @business)
          assert_empty filter.apply(@base_biz_rel).map(&:name)

          filter = ByRepository.new(["#{@org1}/"], [], scope: @business)
          assert_empty filter.apply(@base_biz_rel).map(&:name)

          filter = ByRepository.new(["#{@org1}/my-repo/extra"], [], scope: @business)
          assert_empty filter.apply(@base_biz_rel).map(&:name)
        end
      end

      context "#is_empty?" do
        test "returns 'true' when provided no filters" do
          assert ByRepository.new([], []).is_empty?
        end

        test "returns 'false' when provided inclusive filters" do
          refute ByRepository.new(["test"], []).is_empty?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByRepository.new([], ["test"]).is_empty?
        end

        test "returns 'false' when provided both inclusive and exclusive filters" do
          refute ByRepository.new(["test"], ["test2"]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns 'false' when provided no filters" do
          refute ByRepository.new([], []).has_incl_filters?
        end

        test "returns 'true' when provided inclusive filters" do
          assert ByRepository.new(["test"], []).has_incl_filters?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByRepository.new([], ["test"]).has_incl_filters?
        end

        test "returns 'true' when provided both inclusive and exclusive filters" do
          assert ByRepository.new(["test"], ["test2"]).has_incl_filters?
        end
      end

      private

      def base_query(owner_id:, business_id: nil)
        if business_id.nil?
          Repository.where(owner_id: owner_id)
        else
          Repository
            .where(business_id: business_id)
            .and(
              Repository.where(owner_id: owner_id)
              .or(Repository.where(owner_type: "USER"))
            )
        end
      end

      def create_repo(name, owner:, private: false)
        create(private ? :private_repository : :repository, name: name, owner: owner).tap do |r|
          create(:security_overview_analytics_repository, repository: r)
        end
      end

      def create_ghes_user_repos
        ghes_repo_a = create(:private_repository, owner: @owner, name: "ghes-repo-a").tap do |repo|
          create(:security_overview_analytics_repository, repository: repo)
        end
        ghes_repo_b = create(:private_repository, owner: @owner, name: "ghes-repo-b").tap do |repo|
          create(:security_overview_analytics_repository, repository: repo)
        end

        [ghes_repo_a, ghes_repo_b]
      end
    end
  end
end
