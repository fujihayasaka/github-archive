# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module FilterMappers
    class ToRepositoryIdsTest < GitHub::TestCase
      QueryParser = Search::Queries::SecurityCenter::RiskQueryParser

      fixtures do
        @business = create(:global_business)
        @org = create(:organization, name: "test-org")
        @another_org = create(:organization, name: "another-org")
        @owner = create(:user, name: "#{@org}-owner").tap do |u|
          @org.add_admin(u)
          @another_org.add_admin(u)
          @business.add_owner(u, actor: nil)
        end
        @owner_user_session = create(:user_session, user: @owner)
        @member = create(:user, name: "#{@org}-member").tap do |u|
          @org.add_member(u)
          @another_org.add_member(u)
        end
        @member_user_session = create(:user_session, user: @member)

        team_a_c = create(:team, name: "team-a-c", organization: @org)
        team_b = create(:team, name: "team-b", organization: @org)

        @repo_a = create(:private_repository, owner: @org, name: "repo-a").tap do |repo|
          create(:repository_security_center_config, repository: repo)
          create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo, scanning_count: 0)
          create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 1)
          create(:repository_security_center_status, :dependabot_alerts, :enrolled, repository: repo, scanning_count: 2)
          create(:topic, name: "goku").tap { |t| create(:repository_topic, topic: t, repository: repo) }
          team_a_c.add_repository(repo, :admin)
        end

        @repo_b = create(:public_repository, owner: @org, name: "repo-b").tap do |repo|
          create(:repository_security_center_config, repository: repo)
          create(:repository_security_center_status, :code_scanning, :enrolled, repository: repo, scanning_count: 2)
          create(:repository_security_center_status, :secret_scanning, :not_enrolled, repository: repo, scanning_count: 0)
          create(:repository_security_center_status, :dependabot_alerts, :enrolled, repository: repo, scanning_count: 1)
          create(:topic, name: "vegeta").tap { |t| create(:repository_topic, topic: t, repository: repo) }
          team_b.add_repository(repo, :admin)
        end

        @repo_c = create(:private_repository, owner: @org, name: "repo-c").tap do |repo|
          create(:repository_security_center_config, repository: repo)
          create(:repository_security_center_status, :code_scanning, :enrolled, repository: repo, scanning_count: 1)
          create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 2)
          create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo, scanning_count: 0)
          create(:topic, name: "krillin").tap { |t| create(:repository_topic, topic: t, repository: repo) }
          team_a_c.add_repository(repo, :admin)
        end

        @repo_d = create(:private_repository, owner: @another_org, name: "repo-d").tap do |repo|
          create(:repository_security_center_config, repository: repo)
          create(:repository_security_center_status, :code_scanning, :enrolled, repository: repo, scanning_count: 1)
          create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 2)
          create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo, scanning_count: 0)
          create(:topic, name: "hello").tap { |t| create(:repository_topic, topic: t, repository: repo) }
        end

        @repo_e = create(:private_repository, owner: @another_org, name: "repo-e").tap do |repo|
          create(:repository_security_center_config, repository: repo)
          create(:repository_security_center_status, :code_scanning, :enrolled, repository: repo, scanning_count: 1)
          create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 2)
          create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo, scanning_count: 0)
          create(:topic, name: "world").tap { |t| create(:repository_topic, topic: t, repository: repo) }
        end

        if GitHub.enterprise?
          @ghes_repo_a = create(:private_repository, owner: @owner, name: "ghes-repo-a").tap do |repo|
            create(:repository_security_center_config, repository: repo)
            create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo, scanning_count: 0)
            create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 1)
            create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo, scanning_count: 0)
          end
          @ghes_repo_b = create(:private_repository, owner: @owner, name: "ghes-repo-b").tap do |repo|
            create(:repository_security_center_config, repository: repo)
            create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo, scanning_count: 0)
            create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 1)
            create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo, scanning_count: 0)
          end
        else
          @mt_biz = create(:business, :enterprise_managed, name: "enterprise-managed-business")
          @mt_owner = @mt_biz.find_first_emu_owner
          @mt_owner_session = create(:user_session, user: @mt_owner)
          @mt_user = create(:emu, business: @mt_biz)
          @mt_org = create(:organization, business: @mt_biz, admin: @mt_user, name: "test-mt-org")
          @mt_repo_a = create(:private_repository, owner: @mt_user, name: "mt-repo-a").tap do |repo|
            create(:repository_security_center_config, repository: repo)
            create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo, scanning_count: 0)
            create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 1)
            create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo, scanning_count: 0)
          end
          @mt_repo_b = create(:private_repository, owner: @mt_user, name: "mt-repo-b").tap do |repo|
            create(:repository_security_center_config, repository: repo)
            create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo, scanning_count: 0)
            create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 1)
            create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo, scanning_count: 0)
          end
        end
      end

      context "orgs scope" do
        test "returns empty results when no orgs are provided with no input filters" do
          parser = QueryParser.new("")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new,
            repo_ids_scope: nil,
            orgs: [],
            user: @owner,
            user_session: @owner_user_session,
          )

          assert_equal [[], []], mapper.to_filters
        end

        test "returns FALSE_FILTERS when no orgs are provided with inclusive filters" do
          parser = QueryParser.new("repo")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
            repo_ids_scope: nil,
            orgs: [],
            user: @owner,
            user_session: @owner_user_session,
          )

          assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
        end

        test "returns empty results when no orgs are provided with exclusive filters" do
          parser = QueryParser.new("NOT repo-a")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
            repo_ids_scope: nil,
            orgs: [],
            user: @owner,
            user_session: @owner_user_session,
          )

          assert_equal [[], []], mapper.to_filters
        end

        test "returns repo IDs from multiple orgs with inclusive filters" do
          parser = QueryParser.new("repo")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
            repo_ids_scope: nil,
            orgs: [@org, @another_org],
            user: @owner,
            user_session: @owner_user_session,
          )

          assert_equal [[@repo_a.id, @repo_b.id, @repo_c.id, @repo_d.id, @repo_e.id], []], mapper.to_filters
        end

        test "returns repo IDs from a single org with custom property filters and nil scope" do
          parser = QueryParser.new("props.custom:property")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(custom_properties: parser.custom_properties_query_string),
            repo_ids_scope: nil,
            orgs: [@org],
            user: @owner,
            user_session: @owner_user_session,
          )

          ::SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns([@repo_a.id, @repo_b.id, @repo_c.id])
          assert_equal [[@repo_a.id, @repo_b.id, @repo_c.id], []], mapper.to_filters
        end

        test "returns repo IDs from a single org with custom property filters" do
          parser = QueryParser.new("props.custom:property")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(custom_properties: parser.custom_properties_query_string),
            repo_ids_scope: [@repo_a.id, @repo_b.id, @repo_c.id, @repo_d.id, @repo_e.id],
            orgs: [@org],
            user: @owner,
            user_session: @owner_user_session,
          )

          ::SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns([@repo_a.id, @repo_b.id, @repo_c.id])
          assert_equal [[@repo_a.id, @repo_b.id, @repo_c.id], []], mapper.to_filters
        end

        test "returns negated repo IDs from a single org with custom property filters with nil repo scope" do
          parser = QueryParser.new("-props.custom:property")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(custom_properties: parser.custom_properties_query_string),
            repo_ids_scope: nil,
            orgs: [@org],
            user: @owner,
            user_session: @owner_user_session,
          )

          ::SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns([@repo_a.id, @repo_b.id])
          assert_equal [[], [@repo_a.id, @repo_b.id]], mapper.to_filters
        end

        test "returns negated repo IDs from a single org with custom property filters with repo scope" do
          parser = QueryParser.new("-props.custom:property")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(custom_properties: parser.custom_properties_query_string),
            repo_ids_scope: [@repo_a.id, @repo_b.id, @repo_c.id, @repo_d.id, @repo_e.id],
            orgs: [@org],
            user: @owner,
            user_session: @owner_user_session,
          )

          ::SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns([@repo_c.id])
          assert_equal [[@repo_c.id], []], mapper.to_filters
        end

        test "no repo IDs are filtered from queries with multiple orgs with custom property filters" do
          parser = QueryParser.new("props.custom:property")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(custom_properties: parser.custom_properties_query_string),
            repo_ids_scope: [@repo_a.id, @repo_b.id, @repo_c.id, @repo_d.id, @repo_e.id],
            orgs: [@org, @another_org],
            user: @owner,
            user_session: @owner_user_session,
          )
          Search::Queries::RepoQuery.any_instance.expects(:execute).never
          assert_equal [[@repo_a.id, @repo_b.id, @repo_c.id, @repo_d.id, @repo_e.id], []], mapper.to_filters
        end

        test "returns FALSE FILTERS from queries with a single org that has no repos matching the custom property filters" do
          parser = QueryParser.new("props.custom:property")
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new(custom_properties: parser.custom_properties_query_string),
            repo_ids_scope: [@repo_a.id, @repo_b.id, @repo_c.id, @repo_d.id, @repo_e.id],
            orgs: [@org],
            user: @owner,
            user_session: @owner_user_session,
          )

          ::SecurityCenter::Filters::ByCustomProperty.any_instance.stubs(:es_repo_ids).returns([])
          assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
        end
      end

      context "repo IDs scope" do
        context "no input filters" do
          test "empty scope to FALSE_FILTERS" do
            parser = QueryParser.new("")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new,
              repo_ids_scope: [],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "scope to repo IDs" do
            parser = QueryParser.new("")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new,
              repo_ids_scope: [1, 2, 3],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[1, 2, 3], []], mapper.to_filters
          end
        end

        context "inclusive filters" do
          test "empty scope to FALSE_FILTERS" do
            parser = QueryParser.new("a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: [],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "no matches in scope to FALSE_FILTERS" do
            parser = QueryParser.new("a")
            input_filters = ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers)

            mapper = ToRepositoryIds.new(input_filters, repo_ids_scope: [@repo_b.id], orgs: [@org], user: @owner, user_session: @owner_user_session)
            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters

            # non-existent repo IDs scope
            mapper = ToRepositoryIds.new(input_filters, repo_ids_scope: [Repository.maximum(:id) + 10], orgs: [@org], user: @owner, user_session: @owner_user_session)
            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "matches in scope to repo IDs" do
            parser = QueryParser.new("repo")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: [@repo_a.id],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id], []], mapper.to_filters
          end
        end

        context "exclusive filters" do
          test "empty scope to FALSE_FILTERS" do
            parser = QueryParser.new("NOT a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: [],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "no matches in scope to repo IDs" do
            parser = QueryParser.new("NOT a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: [@repo_b.id],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_b.id], []], mapper.to_filters
          end

          test "matches in scope to repo IDs" do
            parser = QueryParser.new("NOT a,c")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: [@repo_a.id, @repo_b.id],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_b.id], []], mapper.to_filters
          end

          test "to FALSE_FILTERS if all repos in scope are excluded" do
            parser = QueryParser.new("NOT repo")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: [@repo_a.id, @repo_b.id, @repo_c.id],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end
        end

        context "mixed filters" do
          test "matches in scope to repo IDs" do
            parser = QueryParser.new("repo NOT b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: [@repo_a.id, @repo_b.id],
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id], []], mapper.to_filters
          end
        end
      end

      context "no input filters" do
        test "to empty filters" do
          mapper = ToRepositoryIds.new(
            ToRepositoryIds::InputFilters.new,
            repo_ids_scope: nil,
            orgs: [@org],
            user: @owner,
            user_session: @owner_user_session,
          )

          assert_equal [[], []], mapper.to_filters
        end
      end

      context "name substrings" do
        context "inclusive" do
          test "no matches to FALSE_FILTERS" do
            parser = QueryParser.new("no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "filter to repo ID" do
            parser = QueryParser.new("-a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id], []], mapper.to_filters
          end

          test "filter to repo IDs" do
            parser = QueryParser.new("repo")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_b.id, @repo_c.id], []], mapper.to_filters
          end

          test "multiple filters to repo ID" do
            parser = QueryParser.new("repo-a,a,unknown")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id], []], mapper.to_filters
          end

          test "multiple filters to repo IDs" do
            parser = QueryParser.new("a,b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_b.id], []], mapper.to_filters
          end

          test "filter to user-owned repo by repo name" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("repo-a")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id], []], mapper.to_filters
            end
          end

          test "does not return user-owned repos if GHAS is not purchased" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
              parser = QueryParser.new("repo-a")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
            end
          end

          test "filter to user-owned repo by username" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new(@mt_repo_a.owner.display_login)
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id, @mt_repo_b.id], []], mapper.to_filters
            end
          end

          test "filter to multiple user owned repo ID" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("mt-repo-")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id, @mt_repo_b.id], []], mapper.to_filters
            end
          end

          test "filter to single user owned repo using NWO" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new(@mt_repo_a.nwo)
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id], []], mapper.to_filters
            end
          end

          test "filters can mix and match NWO with substrings" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)

              mt_user_b = create(:emu, business: @mt_biz)
              mt_repo_z = create(:private_repository, owner: mt_user_b, name: "mt-repo-z").tap do |repo|
                create(:repository_security_center_config, repository: repo)
                create(:repository_security_center_status, :code_scanning, :not_enrolled, repository: repo, scanning_count: 0)
                create(:repository_security_center_status, :secret_scanning, :enrolled, repository: repo, scanning_count: 1)
                create(:repository_security_center_status, :dependabot_alerts, :not_enrolled, repository: repo, scanning_count: 0)
              end

              parser = QueryParser.new("#{@mt_repo_a.nwo},mt-repo-z")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id, mt_repo_z.id], []], mapper.to_filters
            end
          end

          test "can filter to single user owned repos using NWO on GHES", enterprise_only: true do
            Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

            parser = QueryParser.new(@ghes_repo_a.nwo)
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [],
              user: @owner,
              user_session: @owner_user_session,
              scope: @business,
            )

            assert_equal [[@ghes_repo_a.id], []], mapper.to_filters
          end

          test "does not return user-owned repos if GHAS is not purchased on GHES", enterprise_only: true do
            Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

            parser = QueryParser.new(@ghes_repo_a.nwo)
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [],
              user: @owner,
              user_session: @owner_user_session,
              scope: @business,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end
        end

        context "exclusive" do
          test "no matches to empty filters" do
            parser = QueryParser.new("NOT no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], []], mapper.to_filters
          end

          test "filter to excluded repo ID" do
            parser = QueryParser.new("NOT -a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id]], mapper.to_filters
          end

          test "filter to excluded repo IDs" do
            parser = QueryParser.new("NOT repo")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id, @repo_b.id, @repo_c.id]], mapper.to_filters
          end

          test "multiple filters to excluded repo ID" do
            parser = QueryParser.new("NOT repo-a,a,unknown")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id]], mapper.to_filters
          end

          test "multiple filters to excluded repo IDs" do
            parser = QueryParser.new("NOT a,b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id, @repo_b.id]], mapper.to_filters
          end

          test "single filter can exclude user owned repo ID" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("NOT #{@mt_repo_a.nwo}")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[], [@mt_repo_a.id]], mapper.to_filters
            end
          end

          test "single filter can exclude multiple user owned repo IDs" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("NOT mt-repo")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[], [@mt_repo_a.id, @mt_repo_b.id]], mapper.to_filters
            end
          end

          test "multiple filter can exclude user owned repo IDs" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("NOT a,b")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[], [@mt_repo_a.id, @mt_repo_b.id]], mapper.to_filters
            end
          end
        end

        context "mixed" do
          test "matches to repo IDs" do
            parser = QueryParser.new("repo NOT b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_c.id], []], mapper.to_filters
          end

          test "to FALSE_FILTERS if all included matches are also excluded" do
            parser = QueryParser.new("a NOT repo")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "matches on user owned repo IDs" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              # This test is a little finnicky since something like `NOT b` could
              # inadvertently match against the user of `@mt_repo_a` that we are
              # trying to assert ends up in the result.
              parser = QueryParser.new("mt-repo NOT repo-b")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(name_substrings: parser.values_without_qualifiers),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id], []], mapper.to_filters
            end
          end
        end
      end

      context "names" do
        context "inclusive" do
          test "no matches to FALSE_FILTERS" do
            parser = QueryParser.new("repo:no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "filter to repo ID" do
            parser = QueryParser.new("repo:repo-a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id], []], mapper.to_filters
          end

          test "multiple filters to repo IDs" do
            parser = QueryParser.new("repo:repo-a,repo-b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_b.id], []], mapper.to_filters
          end

          test "filter to single user owned repo ID" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("repo:mt-repo-a")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id], []], mapper.to_filters
            end
          end

          test "filter to multiple user owned repo ID" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("repo:mt-repo-a,mt-repo-b")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id, @mt_repo_b.id], []], mapper.to_filters
            end
          end

          test "can filter for user owned repos on GHES", enterprise_only: true do
            Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
            GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true)
            GitHub.stubs(:security_center_for_emus_enabled?).returns(true)

            parser = QueryParser.new("repo:ghes-repo-a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [],
              user: @owner,
              user_session: @owner_user_session,
              scope: @business,
            )

            assert_equal [[@ghes_repo_a.id], []], mapper.to_filters
          end
        end

        context "exclusive" do
          test "no matches to empty filters" do
            parser = QueryParser.new("-repo:no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], []], mapper.to_filters
          end

          test "filter to excluded repo ID" do
            parser = QueryParser.new("-repo:repo-a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id]], mapper.to_filters
          end

          test "multiple filters to excluded repo IDs" do
            parser = QueryParser.new("-repo:repo-a,repo-b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id, @repo_b.id]], mapper.to_filters
          end

          test "filter to exclude single user owned repo ID" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("-repo:mt-repo-a")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[], [@mt_repo_a.id]], mapper.to_filters
            end
          end

          test "filter to exclude multiple user owned repo ID" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("-repo:mt-repo-a,mt-repo-b")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[], [@mt_repo_a.id, @mt_repo_b.id]], mapper.to_filters
            end
          end
        end

        context "mixed" do
          test "matches to repo IDs" do
            parser = QueryParser.new("repo:repo-a,repo-b,repo-c -repo:repo-b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_c.id], []], mapper.to_filters
          end

          test "to FALSE_FILTERS if all included matches are also excluded" do
            parser = QueryParser.new("repo:repo-a -repo:repo-a")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "matches to user owned repo ID" do
            on_multi_tenant_enterprise do
              Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
              parser = QueryParser.new("repo:mt-repo-a,mt-repo-b -repo:mt-repo-b")
              mapper = ToRepositoryIds.new(
                ToRepositoryIds::InputFilters.new(names: parser.values_for_qualifier(QueryParser::REPOSITORY)),
                repo_ids_scope: nil,
                orgs: [],
                user: @mt_owner,
                user_session: @mt_owner_session,
                scope: @mt_biz,
              )

              assert_equal [[@mt_repo_a.id], []], mapper.to_filters
            end
          end
        end
      end

      context "visibilities" do
        context "inclusive" do
          test "no matches to FALSE_FILTERS" do
            parser = QueryParser.new("is:no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(visibilities: parser.values_for_qualifier(QueryParser::VISIBILITY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "filter to repo ID" do
            parser = QueryParser.new("is:public")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(visibilities: parser.values_for_qualifier(QueryParser::VISIBILITY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_b.id], []], mapper.to_filters
          end

          test "filter to repo IDs" do
            parser = QueryParser.new("is:private")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(visibilities: parser.values_for_qualifier(QueryParser::VISIBILITY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_c.id], []], mapper.to_filters
          end
        end

        context "exclusive" do
          test "no matches to empty filters" do
            parser = QueryParser.new("-is:no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(visibilities: parser.values_for_qualifier(QueryParser::VISIBILITY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], []], mapper.to_filters
          end

          test "filter to excluded repo ID" do
            parser = QueryParser.new("-is:public")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(visibilities: parser.values_for_qualifier(QueryParser::VISIBILITY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_b.id]], mapper.to_filters
          end

          test "filter to excluded repo IDs" do
            parser = QueryParser.new("-is:private")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(visibilities: parser.values_for_qualifier(QueryParser::VISIBILITY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id, @repo_c.id]], mapper.to_filters
          end
        end

        context "mixed" do
          test "matches to repo IDs" do
            parser = QueryParser.new("is:public,private -is:private")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(visibilities: parser.values_for_qualifier(QueryParser::VISIBILITY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_b.id], []], mapper.to_filters
          end

          test "to FALSE_FILTERS if all included matches are also excluded" do
            parser = QueryParser.new("is:public -is:public")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(visibilities: parser.values_for_qualifier(QueryParser::VISIBILITY)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end
        end
      end

      context "topics" do
        context "inclusive" do
          test "no matches to FALSE_FILTERS" do
            parser = QueryParser.new("topic:no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(topics: parser.values_for_qualifier(QueryParser::TOPIC)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "filter to repo ID" do
            parser = QueryParser.new("topic:goku")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(topics: parser.values_for_qualifier(QueryParser::TOPIC)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id], []], mapper.to_filters
          end

          test "multiple filters to repo IDs" do
            parser = QueryParser.new("topic:goku,vegeta")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(topics: parser.values_for_qualifier(QueryParser::TOPIC)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_b.id], []], mapper.to_filters
          end
        end

        context "exclusive" do
          test "no matches to empty filters" do
            parser = QueryParser.new("-topic:no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(topics: parser.values_for_qualifier(QueryParser::TOPIC)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], []], mapper.to_filters
          end

          test "filter to excluded repo ID" do
            parser = QueryParser.new("-topic:goku")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(topics: parser.values_for_qualifier(QueryParser::TOPIC)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id]], mapper.to_filters
          end

          test "multiple filters to excluded repo IDs" do
            parser = QueryParser.new("-topic:goku,vegeta")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(topics: parser.values_for_qualifier(QueryParser::TOPIC)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id, @repo_b.id]], mapper.to_filters
          end
        end

        context "mixed" do
          test "matches to repo IDs" do
            parser = QueryParser.new("topic:goku,vegeta,krillin -topic:vegeta")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(topics: parser.values_for_qualifier(QueryParser::TOPIC)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_c.id], []], mapper.to_filters
          end

          test "to FALSE_FILTERS if all included matches are also excluded" do
            parser = QueryParser.new("topic:goku -topic:goku")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(topics: parser.values_for_qualifier(QueryParser::TOPIC)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end
        end
      end

      context "teams" do
        context "inclusive" do
          test "no matches to FALSE_FILTERS" do
            parser = QueryParser.new("team:no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(teams: parser.values_for_qualifier(QueryParser::TEAM)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end

          test "filter to repo ID" do
            parser = QueryParser.new("team:team-b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(teams: parser.values_for_qualifier(QueryParser::TEAM)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_b.id], []], mapper.to_filters
          end

          test "filter to repo IDs" do
            parser = QueryParser.new("team:team-a-c")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(teams: parser.values_for_qualifier(QueryParser::TEAM)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_a.id, @repo_c.id], []], mapper.to_filters
          end
        end

        context "exclusive" do
          test "no matches to empty filters" do
            parser = QueryParser.new("-team:no-match")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(teams: parser.values_for_qualifier(QueryParser::TEAM)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], []], mapper.to_filters
          end

          test "filter to excluded repo ID" do
            parser = QueryParser.new("-team:team-b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(teams: parser.values_for_qualifier(QueryParser::TEAM)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_b.id]], mapper.to_filters
          end

          test "filter to excluded repo IDs" do
            parser = QueryParser.new("-team:team-a-c")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(teams: parser.values_for_qualifier(QueryParser::TEAM)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[], [@repo_a.id, @repo_c.id]], mapper.to_filters
          end
        end

        context "mixed" do
          test "matches to repo IDs" do
            parser = QueryParser.new("team:team-b,team-a-c -team:team-a-c")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(teams: parser.values_for_qualifier(QueryParser::TEAM)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal [[@repo_b.id], []], mapper.to_filters
          end

          test "to FALSE_FILTERS if all included matches are also excluded" do
            parser = QueryParser.new("team:team-b -team:team-b")
            mapper = ToRepositoryIds.new(
              ToRepositoryIds::InputFilters.new(teams: parser.values_for_qualifier(QueryParser::TEAM)),
              repo_ids_scope: nil,
              orgs: [@org],
              user: @owner,
              user_session: @owner_user_session,
            )

            assert_equal ToRepositoryIds::FALSE_FILTERS, mapper.to_filters
          end
        end
      end
    end
  end
end
