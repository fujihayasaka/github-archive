# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Coverage
    class CoverageListDataQueryTest < GitHub::TestCase
      include GitHub::Memoizer
      include DogstatsTestHelpers
      include DuplicateQueryTestHelper

      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

      fixtures do
        # Business
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @business = create(:global_business)

        @owner = create(:user).tap do |u|
          create_repo("#{u}-ss-repo", owner: u,
            features: {
              secret_scanning: { status: :enrolled },
              secret_scanning_push_protection: { status: :enrolled },
            }
          )
          create_repo("#{u}-ss-pp-repo", owner: u,
            features: {
              secret_scanning: { status: :enrolled },
              secret_scanning_push_protection: { status: :enrolled },
            }
          )
        end

        # Orgs, repos, and teams
        @org1 = create(:business_plus_organization, business: @business, admin: @owner, name: "test-org-1").tap do |o|
          @cs_repo = create_repo("#{o}-cs-repo", owner: o,
            features: {
              code_scanning: { status: :enrolled },
              code_scanning_pr_reviews: { status: :enrolled },
            }
          )
          @dbot_repo = create_repo("#{o}-dbot-repo", owner: o,
            features: {
              dependabot_alerts: { status: :enrolled },
              dependabot_security_updates: { status: :enrolled },
            }
          )
          @ss_repo = create_repo("#{o}-ss-repo", owner: o,
            features: {
              secret_scanning: { status: :enrolled },
              secret_scanning_push_protection: { status: :enrolled },
            }
          )
          @mixed_repo = create_repo("#{o}-mixed-repo", owner: o,
            features: {
              code_scanning: { status: :enrolled },
              dependabot_alerts: { status: :enrolled },
              secret_scanning: { status: :enrolled },
            }
          )

          create(:team, name: "#{o}-mixed-repo-team", organization: o).tap { |team| team.add_repository(@mixed_repo, :admin) }
          create(:topic, name: "apples").tap { |t| create(:repository_topic, topic: t, repository: @cs_repo) }
          create(:topic, name: "oranges").tap { |t| create(:repository_topic, topic: t, repository: @dbot_repo) }
        end

        @org2 = create(:business_plus_organization, business: @business, admin: @owner, name: "test-org-2").tap do |o|
          create_repo("#{o}-repo", owner: o)
        end

        @org3 = create(:business_plus_organization, business: @business, name: "test-org-3").tap do |o|
          create_repo("#{o}-repo", owner: o,
            features: {
              code_scanning: { status: :enrolled },
              code_scanning_auto_codeql: { status: :enrolled },
            }
          )
          create_repo("#{o}-repo2", owner: o,
            features: {
              code_scanning: { status: :enrolled },
              code_scanning_auto_codeql: { status: :eligible },
            }
          )
        end

        unless GitHub.enterprise?
          @mt_user = create(:emu)
          @mt_biz = @mt_user.enterprise_managed_business
          @mt_biz_owner = @mt_biz.owners.first

          @mt_user.tap do |o|
            @mt_user_ss_repo = create_repo("#{o}-mt-user-ss-repo", owner: @mt_user,
              features: {
                secret_scanning: { status: :enrolled },
                secret_scanning_push_protection: { status: :enrolled },
              })
            @mt_user_no_alerts_repo = create_repo("#{o}-mt-user-no-features-repo", owner: @mt_user, features: {})
          end

          @mt_org = create(:business_plus_organization, business: @mt_biz, admin: @mt_user, name: "mt-org-1").tap do |o|
            @mt_org_mixed_repo = create_repo("#{o}-mt-org-mixed-repo", owner: o,
              features: {
                code_scanning: { status: :enrolled },
                dependabot_alerts: { status: :enrolled },
                secret_scanning: { status: :enrolled },
              })
          end

          enterprise_security_manager_team = create :enterprise_security_manager_team, business: @mt_biz
          @enterprise_security_manager = create :emu
          @mt_org.add_member @enterprise_security_manager # Because the factory doesn't set up the org teams sync
          enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
        end
      end

      setup do
        @parser = CoverageQueryParser.new("")
        Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

        SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns(@org1.repositories.pluck(:id))
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      end

      # Returns an array of 2-tuples of the form [[pos_filter, neg_filter], expected_query_count]
      def self.basic_filters_and_sort_with_query_counts
        # Author these to always match at least one repo so we can evaluate how many queries are made.
        [
          [["repo", "NOT mixed"], 1],
          [["archived:false", "-archived:true"], 1],
          [["code-scanning-alerts:enabled", "-code-scanning-alerts:disabled"], 1],
          [["code-scanning-pull-request-alerts:enabled", "-code-scanning-pull-request-alerts:disabled"], 1],
          [["code-scanning-default-setup:eligible", "-code-scanning-auto-codeql:not-eligible"], 1],
          [["dependabot-alerts:enabled", "-dependabot-alerts:disabled"], 1],
          [["dependabot-security-updates:enabled", "-dependabot-security-updates:disabled"], 1],
          [["advanced-security:enabled", "-advanced-security:disabled"], 1],
          [["is:private", "-is:public"], 1],
          [["owner:test-org-1", "-owner:whatever2"], 1],
          [["owner-type:organization", "-owner-type:user"], 1],
          [["repo:test-org-1-mixed-repo", "-repo:whatever"], 1],
          [["secret-scanning-alerts:enabled", "-secret-scanning-alerts:disabled"], 1],
          [["secret-scanning-push-protection:enabled", "-secret-scanning-push-protection:disabled"], 1],
          [["sort:repos", "sort:last-updated"], 1],
          [["team:test-org-1-mixed-repo-team", "-team:test-org-1-mixed-repo-team"], 5],
          [["topic:apples", "-topic:oranges"], 3],
          [["props.custom:property", "-props.custom:property"], 1],
        ]
      end

      context "#all" do
        basic_filters_and_sort_with_query_counts.each do |filters, query_count|
          filters.each do |filter|
            test "basic test exercising filter: #{filter.start_with?("-") ? filter.sub("-", "negated ") : filter}" do
              @parser = CoverageQueryParser.new(filter)
              assert_nothing_raised do
                assert_queries(count: query_count) do
                  ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser).all.to_a
                end
              end
            end
          end
        end

        test "basic test exercising all filters at once" do
          all_filters = self.class.basic_filters_and_sort_with_query_counts.map(&:first).flatten.join(" ")
          @parser = CoverageQueryParser.new(all_filters)

          # Make sure we're using all qualifiers, plus unqualified text
          assert_equal CoverageQueryParser::QUALIFIERS.size + 1, self.class.basic_filters_and_sort_with_query_counts.size

          assert_nothing_raised do
            assert_queries(count: 13) do
              ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser).all.to_a
            end
          end
        end

        test "returns results only for the provided organization" do
          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser).all.to_a
          end.tap do |result|
            expected_repos = @org1.repositories
            assert_equal expected_repos.size, result.size
            assert_same_elements \
              expected_repos.map(&:name),
              result.map { |r| r.name }
          end

          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org2, parser: @parser).all.to_a
          end.tap do |result|
            expected_repos = @org2.repositories
            assert_equal expected_repos.size, result.size
            assert_same_elements \
              expected_repos.map(&:id),
              result.map { |r| r.repository_id }
          end
        end

        context "for businesses with enterprise managed users on Dotcom", skip_enterprise: true do
          context "includes EMU-owned repos" do
            test "as business owner with own repos" do
              assert_queries(count: GitHub.flipper[:business_esm_check_permission_via_authz_domain].enabled? ? 1 : 2) do
                ListDataQuery.for_organizations(user: @mt_biz_owner, business: @mt_biz, organizations: [@mt_org], parser: CoverageQueryParser.new("")).all.to_a
              end.tap do |result|
                expected_repos = @mt_org.repositories + @mt_user.repositories
                assert_equal expected_repos.size, result.size
                assert_same_elements \
                  expected_repos.map(&:id),
                  result.map { |r| r.repository_id }
              end
            end

            test "as business owner with repos owned by another user" do
              assert_queries(count: GitHub.flipper[:business_esm_check_permission_via_authz_domain].enabled? ? 1 : 2) do
                ListDataQuery.for_organizations(user: @mt_biz_owner, business: @mt_biz, organizations: [@mt_org], parser: CoverageQueryParser.new("")).all.to_a
              end.tap do |result|
                expected_repos = @mt_org.repositories + @mt_user.repositories
                assert_equal expected_repos.size, result.size
                assert_same_elements \
                  expected_repos.map(&:id),
                  result.map { |r| r.repository_id }
              end
            end

            test "as enterprise security manager with repos owned by another user" do
              assert_queries(count: GitHub.flipper[:business_esm_check_permission_via_authz_domain].enabled? ? 1 : 2) do
                ListDataQuery.for_organizations(user: @enterprise_security_manager, business: @mt_biz, organizations: [@mt_org], parser: CoverageQueryParser.new("")).all.to_a
              end.tap do |result|
                expected_repos = @mt_org.repositories + @mt_user.repositories
                assert_equal expected_repos.size, result.size
                assert_same_elements \
                  expected_repos.map(&:id),
                  result.map { |r| r.repository_id }
              end
            end
          end

          test "excludes EMU-owned repos if GHAS is not purchased" do
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            assert_queries(count: 1) do
              ListDataQuery.for_organizations(user: @mt_user, business: @mt_biz, organizations: [@mt_org], parser: CoverageQueryParser.new("")).all.to_a
            end.tap do |result|
              expected_repos = @mt_org.repositories
              assert_equal expected_repos.size, result.size
              assert_same_elements \
                expected_repos.map(&:id),
                result.map { |r| r.repository_id }
            end
          end
        end

        context "for businesses without enterprise managed users on Dotcom", skip_enterprise: true do
          test "does not include user-owned repos" do
            assert_queries(count: 1) do
              ListDataQuery.for_organizations(user: @owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new("")).all.to_a
            end.tap do |result|
              expected_repos = @org1.repositories + @org2.repositories
              assert_equal expected_repos.size, result.size
              assert_same_elements \
                expected_repos.map(&:id),
                result.map { |r| r.repository_id }
            end
          end
        end

        context "for businesses with user-owned repositories on GHES", enterprise_only: true do
          context "includes user-owned repos if feature flag is enabled" do
            test "for business owner with own repos" do
              GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

              @business.add_owner(@owner, actor: nil)

              assert_queries(count: 2) do
                ListDataQuery.for_organizations(user: @owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new("")).all.to_a
              end.tap do |result|
                expected_repos = @org1.repositories + @org2.repositories + @owner.repositories
                assert_equal expected_repos.size, result.size
                assert_same_elements \
                  expected_repos.map(&:id),
                  result.map { |r| r.repository_id }
              end
            end

            test "for business owner with repos owned by another user" do
              GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

              other_biz_owner = create(:user)
              @business.add_owner(other_biz_owner, actor: nil)

              assert_queries(count: 2) do
                ListDataQuery.for_organizations(user: other_biz_owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new("")).all.to_a
              end.tap do |result|
                expected_repos = @org1.repositories + @org2.repositories + @owner.repositories
                assert_equal expected_repos.size, result.size
                assert_same_elements \
                  expected_repos.map(&:id),
                  result.map { |r| r.repository_id }
              end
            end
          end

          test "excludes user-owned repos if GHAS is not purchased" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

            assert_queries(count: 1) do
              ListDataQuery.for_organizations(user: @owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new("")).all.to_a
            end.tap do |result|
              expected_repos = @org1.repositories + @org2.repositories
              assert_equal expected_repos.size, result.size
              assert_same_elements \
                expected_repos.map(&:id),
                result.map { |r| r.repository_id }
            end
          end

          test "excludes user-owned repos if feature flag is disabled" do
            GitHub.stubs(:security_center_for_emus_enabled?).returns(false)

            assert_queries(count: 1) do
              ListDataQuery.for_organizations(user: @owner, business: @business, organizations: [@org1, @org2], parser: CoverageQueryParser.new("")).all.to_a
            end.tap do |result|
              expected_repos = @org1.repositories + @org2.repositories
              assert_equal expected_repos.size, result.size
              assert_same_elements \
                expected_repos.map(&:id),
                result.map { |r| r.repository_id }
            end
          end
        end

        test "returns results limited by provided repository ids" do
          # no filter
          expected = [@cs_repo, @dbot_repo, @ss_repo, @mixed_repo]
          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, repo_ids: nil, parser: @parser).all.to_a
          end.tap do |result|
            assert_equal expected.size, result.size
            assert_same_elements \
              expected.map(&:id),
              result.map { |r| r.repository_id }
          end

          # partial filter
          expected = [@cs_repo, @dbot_repo, @ss_repo]
          assert_queries(count: 1) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, repo_ids: expected.map(&:id), parser: @parser).all.to_a
          end.tap do |result|
            assert_equal expected.size, result.size
            assert_same_elements \
              expected.map(&:id),
              result.map { |r| r.repository_id }
          end

          # all filter
          expected = []
          assert_queries(count: 0) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, repo_ids: expected.map(&:id), parser: @parser).all.to_a
          end.tap do |result|
            assert_empty result
          end
        end

        test "returns filtered repo relation for org" do
          # returns unexecuted relation
          rel = assert_queries(count: 0) do
            ListDataQuery.for_organization(user: @owner, organization: @org1, parser: @parser).all
          end

          assert_queries(count: 1) do
            rel.to_a
          end.tap do |result|
            assert_equal @org1.repositories.active.not_archived_scope.length, result.length
          end
        end
      end

      private

      sig { returns(UrlHelpers) }
      memoize def urls
        T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
      end

      def assert_queries(count: 0)
        result = T.let(nil, T.untyped)
        assert_query_count(count, ignore_feature_flags: true) do
          assert_duplicate_query_detection(ListDataQuery, 0) do
            result = yield
          end
        end

        result
      end

      def create_repo(name, owner:, visibility: :private, archived: false, features: {}, create_statuses_for_unspecified_features: true)
        factory = if visibility == :private
          :private_repository
        elsif visibility == :public
          :repository
        elsif visibility == :internal
          :internal_repository
        end

        create(factory, name: name, owner: owner).tap do |r|
          r.set_archived if archived

          create_config(r)

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          features.each do |feature, opts|
            opts => { status: }
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, status: status)
          end

          if create_statuses_for_unspecified_features
            (all_feature_types - features.keys).each do |feature|
              create_status(r, feature: feature, status: :not_enrolled)
            end
          end
        end
      end

      def create_workspace_repo(source_repo, actor:)
        GitHub.context.push(actor_id: actor.id) # Avoids `ActiveRecord::RecordInvalid: Validation failed: Updater must exist`
        advisory = create(:repository_advisory, repository: source_repo, author: actor)
        workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, actor).tap do |r|
          r.save!

          create_config(r)

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          all_feature_types.each do |feature|
            create_status(r, feature: feature, status: :not_enrolled)
          end
        end
      end

      def create_config(repo)
        create(
          :repository_security_center_config,
          repository: repo,
          ghas_enabled: true,
        )
      end

      def create_status(repo, feature:, status:)
        create(
          :repository_security_center_status,
          feature,
          scanning_status: status,
          repository: repo,
        )
      end
    end
  end
end
