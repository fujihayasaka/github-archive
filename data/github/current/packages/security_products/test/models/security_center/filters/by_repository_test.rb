# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
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
          @mt_org_repo = create(:private_repository, owner: @mt_org, name: "mt-repo-a").tap do |repo|
            create(:repository_security_center_config, repository: repo)
            create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo)
            create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)
            create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo)
          end
          @mt_repo_a = create(:private_repository, owner: @mt_user, name: "mt-repo-a").tap do |repo|
            create(:repository_security_center_config, repository: repo)
            create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo)
            create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)
            create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo)
          end
          @mt_repo_b = create(:private_repository, owner: @mt_user, name: "mt-repo-b").tap do |repo|
            create(:repository_security_center_config, repository: repo)
            create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo)
            create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)
            create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo)
          end
        end
      end

      context "#apply" do
        context "substring matching" do
          test "filters by partial repository name" do
            rel = base_query(owner_id: @org.id)

            filter = ByRepository.new([], [], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

            filter = ByRepository.new(["unknown"], [], substring_match: true)
            assert_empty filter.apply(rel).map(&:repository_id)

            filter = ByRepository.new([@repo_a.name], [], substring_match: true)
            expected_repos = [@repo_a]
            assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

            filter = ByRepository.new(["repo-a"], [], substring_match: true)
            expected_repos = [@repo_a]
            assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

            filter = ByRepository.new(["repo"], [], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

            filter = ByRepository.new([], ["unknown"], substring_match: true)
            expected_repos = [@repo_a, @repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

            filter = ByRepository.new([], [@repo_a.name], substring_match: true)
            expected_repos = [@repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

            filter = ByRepository.new([], ["repo-a"], substring_match: true)
            expected_repos = [@repo_b, @repo_c]
            assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

            filter = ByRepository.new([], ["repo"], substring_match: true)
            assert_empty filter.apply(rel).map(&:repository_id)
          end

          context "business scope" do
            test "filters by partial standalone repo or org name" do
              rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

              filter = ByRepository.new([], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["unknown"], [], substring_match: true, scope: @business)
              assert_empty filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([@repo3.name], [], substring_match: true, scope: @business)
              expected_repos = [@repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["my-repo"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["repo"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["org-2"], [], substring_match: true, scope: @business)
              expected_repos = [@repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(%w[repo thing], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["unknown"], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], [@repo3.name], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["repo"], substring_match: true, scope: @business)
              expected_repos = [@repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["org-2"], substring_match: true, scope: @business)
              expected_repos = [@repo1]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], %w[repo thing], substring_match: true, scope: @business)
              assert_empty filter.apply(rel).map(&:repository_id)
            end

            test "filters by partial repo name within org if NWO is provided" do
              rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

              filter = ByRepository.new(["#{@org1.name}/unknown"], [], substring_match: true, scope: @business)
              assert_empty filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org1.name}/another"], [], substring_match: true, scope: @business)
              assert_empty filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org2.name}/another"], [], substring_match: true, scope: @business)
              expected_repos = [@repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org1.name}/my-"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org1.name}/my-", "#{@org2.name}/another"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org2.name}/"], [], substring_match: true, scope: @business)
              expected_repos = [@repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org1.name}/unknown"], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org2.name}/another"], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org1.name}/my-"], substring_match: true, scope: @business)
              expected_repos = [@repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org1.name}/my-", "#{@org2.name}/another"], substring_match: true, scope: @business)
              expected_repos = [@repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
            end

            test "filters by a combination of standalone repo names and NWOs" do
              rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

              filter = ByRepository.new(["#{@org2.name}/another", "my-repo"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo2, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["another", "#{@org1.name}/my-"], [], substring_match: true, scope: @business)
              expected_repos = [@repo1, @repo3]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org1.name}/my-", "another"], substring_match: true, scope: @business)
              expected_repos = [@repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new([], ["#{@org2.name}/another", "repo"], substring_match: true, scope: @business)
              assert_empty filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["repo"], ["#{@org1.name}/my-"], substring_match: true, scope: @business)
              expected_repos = [@repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

              filter = ByRepository.new(["#{@org2.name}/"], ["another"], substring_match: true, scope: @business)
              expected_repos = [@repo2]
              assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
            end

            context "for emus" do
              test "filters by partial standalone repo or user name" do
                on_multi_tenant_enterprise do
                  rel = base_query(owner_id: @mt_biz.organizations.map(&:id), business_id: @mt_biz.id)

                  filter = ByRepository.new([], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["unknown"], [], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([@mt_repo_b.name], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["mt-repo-a"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["repo-a"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([@mt_user.name], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["repo-b"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(%w[repo thing], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  # negations
                  filter = ByRepository.new([], ["unknown"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], [@mt_repo_b.name], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], ["repo-a"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], [@mt_user.name], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], %w[repo thing], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(rel).map(&:repository_id)
                end
              end

              test "filters by partial repo name if NWO is provided" do
                on_multi_tenant_enterprise do
                  rel = base_query(owner_id: @mt_biz.organizations.map(&:id), business_id: @mt_biz.id)

                  filter = ByRepository.new(["#{@mt_user.name}/unknown"], [], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_org.name}/unknown"], [], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_user.name}/mt-repo-b"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_user.name}/mt-"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_org.name}/mt-", "#{@mt_user.name}/mt-"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_user.name}/"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  # negations
                  filter = ByRepository.new([], ["#{@mt_user.name}/unknown"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], ["#{@mt_user.name}/mt-repo-b"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], ["#{@mt_org.name}/mt-"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], ["#{@mt_org.name}/mt-", "#{@mt_user.name}/mt-repo-b"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_a]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
                end
              end

              test "filters by a combination of standalone repo names and NWOs" do
                on_multi_tenant_enterprise do
                  rel = base_query(owner_id: @mt_biz.organizations.map(&:id), business_id: @mt_biz.id)

                  filter = ByRepository.new([@mt_repo_b.nwo, "mt-repo-a"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a, @mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["repo-a", "#{@mt_org.name}/mt-"], [], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo, @mt_repo_a]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  # negations
                  filter = ByRepository.new([], ["#{@mt_org.name}/mt-", "mt-repo-a"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], ["#{@mt_org.name}/mt-", "repo-a", "repo-b"], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new([], ["repo"], substring_match: true, scope: @mt_biz)
                  assert_empty filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["repo"], [@mt_repo_a.nwo, "mt-repo-b"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_org_repo]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                  filter = ByRepository.new(["#{@mt_user.name}/"], ["repo-a"], substring_match: true, scope: @mt_biz)
                  expected_repos = [@mt_repo_b]
                  assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
                end
              end
            end

            context "on ghes", enterprise_only: true do
              test "filters by partial standalone user name" do
                ghes_repo_a, ghes_repo_b = create_ghes_user_repos
                rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

                filter = ByRepository.new([ghes_repo_a.name], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new(["ghes-repo"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new(["repo-a"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new(%w(ghes-repo thing), [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a, ghes_repo_b, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                # negations
                filter = ByRepository.new([], ["ghes-repo"], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new([], [ghes_repo_a.name], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new([], [@owner.name], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
              end

              test "filters by partial repo name with NWOs" do
                ghes_repo_a, ghes_repo_b = create_ghes_user_repos
                rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

                filter = ByRepository.new(["#{@owner.name}/ghes-"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new(["#{@owner.name}/ghes-repo-a"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new(["#{@owner.name}/"], [], substring_match: true, scope: @business)
                expected_repos = [ghes_repo_a, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                # negations
                filter = ByRepository.new([], ["#{@owner.name}/"], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new([], ["#{@owner.name}/ghes-"], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

                filter = ByRepository.new([], ["#{@owner.name}/ghes-repo-b"], substring_match: true, scope: @business)
                expected_repos = [@repo1, @repo2, @repo3, ghes_repo_a]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
              end

              test "filters by a combination of standalone repo names and NWOs" do
                ghes_repo_a, ghes_repo_b = create_ghes_user_repos
                rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

                filter = ByRepository.new(["ghes-repo", "#{@org2.name}/another"], [], substring_match: true, scope: @business)
                expected_repos = [@repo3, ghes_repo_a, ghes_repo_b]
                assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)
              end
            end
          end
        end

        test "filters by repository name" do
          rel = RepositorySecurityCenterConfig.where(owner_id: @org.id).left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          filter = ByRepository.new([], [])
          expected_repos = [@repo_a, @repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByRepository.new([@repo_a.name], [])
          expected_repos = [@repo_a]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByRepository.new([@repo_b.name], [])
          expected_repos = [@repo_b]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByRepository.new([], [@repo_a.name])
          expected_repos = [@repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByRepository.new([], [@repo_b.name])
          expected_repos = [@repo_a, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          filter = ByRepository.new(["unknown"], [])
          assert_empty filter.apply(rel).map(&:repository_id)

          filter = ByRepository.new([], ["unknown"])
          expected_repos = [@repo_a, @repo_b, @repo_c]
          assert_same_elements expected_repos.map(&:id), filter.apply(rel).map(&:repository_id)

          # For EMUs
          # recall that the name of @mt_repo_a and @mt_org_repo are the same
          on_multi_tenant_enterprise do
            expected_mt_repos = T.let([], T::Array[Repository])
            new_rel = base_query(owner_id: @mt_org.id, business_id: @mt_biz.id)

            filter = ByRepository.new([], [], scope: @mt_biz)
            expected_mt_repos = [@mt_repo_a, @mt_repo_b, @mt_org_repo]
            assert_same_elements expected_mt_repos.map(&:id), filter.apply(new_rel).map(&:repository_id)

            filter = ByRepository.new([@mt_repo_b.name], [], scope: @mt_biz)
            expected_mt_repos = [@mt_repo_b]
            assert_same_elements expected_mt_repos.map(&:id), filter.apply(new_rel).map(&:repository_id)

            filter = ByRepository.new([@mt_repo_a.name], [], scope: @mt_biz)
            expected_mt_repos = [@mt_repo_a, @mt_org_repo]
            assert_same_elements expected_mt_repos.map(&:id), filter.apply(new_rel).map(&:repository_id)

            filter = ByRepository.new([], [@mt_repo_a.name], scope: @mt_biz)
            expected_mt_repos = [@mt_repo_b]
            assert_same_elements expected_mt_repos.map(&:id), filter.apply(new_rel).map(&:repository_id)
          end
        end

        test "doesn't apply clause if no filters are provided" do
          rel = base_query(owner_id: @org.id)
          expected_clause = rel.to_sql

          filter = ByRepository.new(nil, nil)
          assert_equal expected_clause, filter.apply(rel).to_sql

          filter = ByRepository.new([], [])
          assert_equal expected_clause, filter.apply(rel).to_sql
        end

        test "returns proper result for is_empty?" do
          assert ByRepository.new(nil, nil).is_empty?
          assert ByRepository.new([], []).is_empty?
          refute ByRepository.new(["test"], []).is_empty?
          refute ByRepository.new([], ["test"]).is_empty?
        end

        test "applies where clause with positive filters" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByRepository.new([@repo_a.name], [])
          expected_clause = "WHERE `repository_security_center_configs`.`name` = '#{@repo_a.name}'"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with negated filters" do
          rel = RepositorySecurityCenterConfig.all
          prefix_sql = rel.to_sql

          filter = ByRepository.new([], [@repo_a.name])
          expected_clause = "WHERE `repository_security_center_configs`.`name` != '#{@repo_a.name}'"
          assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
        end

        test "applies where clause with positive filter for EMUs" do
          on_multi_tenant_enterprise do
            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new([@mt_repo_a.name], [], scope: @business)
            expected_clause = "WHERE `repository_security_center_configs`.`name` = '#{@mt_repo_a.name}'"
            assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
          end
        end

        test "applies where clause with negative filter for EMUs" do
          on_multi_tenant_enterprise do
            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new([], [@mt_repo_a.name], scope: @business)
            expected_clause = "WHERE `repository_security_center_configs`.`name` != '#{@mt_repo_a.name}'"
            assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
          end
        end

        test "filters by repo name across orgs" do
          rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

          filter = ByRepository.new(["my-repo"], [], scope: @business)
          expected_repos = [@repo1, @repo2]
          assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)
        end

        test "filters by repo name across EMUs" do
          on_multi_tenant_enterprise do
            other_user = create(:emu, business: @mt_biz)
            other_mt_repo_a = create(:private_repository, owner: other_user, name: "mt-repo-a").tap do |repo|
              create(:repository_security_center_config, repository: repo)
              create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo)
              create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)
              create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo)
            end

            rel = base_query(owner_id: @mt_biz.organizations.map(&:id), business_id: @mt_biz.id)

            filter = ByRepository.new(["mt-repo-a"], [], scope: @business)
            expected_repos = [@mt_org_repo, @mt_repo_a, other_mt_repo_a]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)
          end
        end

        test "filters by repo nwo within specified org" do
          rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

          filter = ByRepository.new(["#{@org1}/my-repo"], [], scope: @business)
          expected_repos = [@repo1]
          assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)
        end

        test "filters by repo nwo within specific EMU" do
          on_multi_tenant_enterprise do
            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new([@mt_repo_a.nwo], [], scope: @business)
            expected_clause = "WHERE (1=0 OR `repository_security_center_configs`.`owner_id` = #{@mt_user.id} AND `repository_security_center_configs`.`name` = '#{@mt_repo_a.name}')"
            assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
          end
        end

        context "filters by repo NWO on GHES", enterprise_only: true do
          test "filter by repo name" do
            ghes_repo_a, ghes_repo_b = create_ghes_user_repos

            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new([ghes_repo_a.name], [], scope: @business)
            result = filter.apply(rel)
            expected_clause = "WHERE `repository_security_center_configs`.`name` = '#{ghes_repo_a.name}'"
            assert_equal expected_clause, result.to_sql.delete_prefix(prefix_sql).strip

            expected_repos = [ghes_repo_a]
            assert_same_elements expected_repos.map(&:name), result.map(&:name)
          end

          test "filter by repo name with negation" do
            ghes_repo_a, ghes_repo_b = create_ghes_user_repos

            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new([], [ghes_repo_a.name], scope: @business)
            result = filter.apply(rel)
            expected_clause = "WHERE `repository_security_center_configs`.`name` != '#{ghes_repo_a.name}'"
            assert_equal expected_clause, result.to_sql.delete_prefix(prefix_sql).strip

            expected_repos = [@repo_a, @repo_b, @repo_c, @repo1, @repo2, @repo3, ghes_repo_b]
            assert_same_elements expected_repos.map(&:name), result.map(&:name)
          end

          test "filter by repo nwo" do
            ghes_repo_a, ghes_repo_b = create_ghes_user_repos

            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new([ghes_repo_a.nwo], [], scope: @business)
            result = filter.apply(rel)

            expected_repos = [ghes_repo_a]
            assert_same_elements expected_repos.map(&:name), result.map(&:name)
          end

          test "returns no results for unknown user" do
            ghes_repo_a, ghes_repo_b = create_ghes_user_repos

            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new(["#{@owner.name}/jhghjb"], [], scope: @business)
            result = filter.apply(rel)

            expected_repos = []
            assert_same_elements expected_repos.map(&:name), result.map(&:name)
          end
        end

        test "returns no results for unknown org in a repo nwo filter" do
          rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

          filter = ByRepository.new(["unknown-org/my-repo"], [], scope: @business)
          assert_empty filter.apply(rel).map(&:name)
        end

        test "returns no results for unknown repo in a nwo filter" do
          rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

          filter = ByRepository.new(["#{@org1}/unknown-repo"], [], scope: @business)
          assert_empty filter.apply(rel).map(&:name)
        end

        test "returns no results for unknown EMU in a repo nwo filter" do
          on_multi_tenant_enterprise do
            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new(["unknown/#{@mt_repo_a.name}"], [], scope: @business)
            assert_empty filter.apply(rel).map(&:name)
          end
        end

        test "returns no results for unknown EMU repo in a nwo filter" do
          on_multi_tenant_enterprise do
            rel = RepositorySecurityCenterConfig.all
            prefix_sql = rel.to_sql

            filter = ByRepository.new(["#{@mt_user}/foobar"], [], scope: @business)
            assert_empty filter.apply(rel).map(&:name)
          end
        end

        test "returns no results for invalid repo nwo filter" do
          rel = base_query(owner_id: @business.organizations.map(&:id), business_id: @business.id)

          filter = ByRepository.new(["/my-repo"], [], scope: @business)
          assert_empty filter.apply(rel).map(&:name)

          filter = ByRepository.new(["#{@org1}/"], [], scope: @business)
          assert_empty filter.apply(rel).map(&:name)

          filter = ByRepository.new(["#{@org1}/my-repo/extra"], [], scope: @business)
          assert_empty filter.apply(rel).map(&:name)
        end
      end

      def create_repo(name, owner:, visibility: :private, archived: false, enabled_features: [], not_enabled_features: [], create_not_enabled_statuses_for_unspecified_features: true)
        factory = if visibility == :private
          :private_repository
        elsif visibility == :public
          :repository
        elsif visibility == :internal
          :internal_repository
        end

        create(factory, name: name, owner: owner).tap do |r|
          r.set_archived if archived

          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: true,
          )

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          enabled_features.each do |feature|
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, enrolled: true)
          end

          not_enabled_features.each do |feature|
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, enrolled: false)
          end

          if create_not_enabled_statuses_for_unspecified_features
            (all_feature_types - enabled_features - not_enabled_features).each do |feature|
              create_status(r, feature: feature, enrolled: false)
            end
          end
        end
      end

      def base_query(owner_id:, business_id: 0)
        if business_id == 0
          RepositorySecurityCenterConfig
            .where(owner_id: owner_id)
            .left_outer_joins(:repository_security_center_statuses)
            .group(:repository_id)
        else
          RepositorySecurityCenterConfig
            .where(business_id: business_id)
            .and(
              RepositorySecurityCenterConfig.where(owner_id: owner_id)
              .or(RepositorySecurityCenterConfig.where(owner_type: "USER"))
            )
            .left_outer_joins(:repository_security_center_statuses)
            .group(:repository_id)
        end
      end

      def create_status(repo, feature:, enrolled:)
        create(
          :repository_security_center_status,
          feature,
          enrolled ? :enrolled : :not_enrolled,
          repository: repo,
        )
      end

      def create_ghes_user_repos
        ghes_repo_a = create(:private_repository, owner: @owner, name: "ghes-repo-a").tap do |repo|
          create(:repository_security_center_config, repository: repo)
          create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo)
          create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)
          create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo)
        end
        ghes_repo_b = create(:private_repository, owner: @owner, name: "ghes-repo-b").tap do |repo|
          create(:repository_security_center_config, repository: repo)
          create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo)
          create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo)
          create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo)
        end

        [ghes_repo_a, ghes_repo_b]
      end
    end
  end
end
