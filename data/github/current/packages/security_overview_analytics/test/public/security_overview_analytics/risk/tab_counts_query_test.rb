# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Risk
    class TabCountsQueryTest < GitHub::TestCase

      fixtures do
        @org_owner = create(:user)
        @org_owner_session = create(:user_session, user: @org_owner)
        @org = create(:organization, admin: @org_owner)
      end

      setup do
        Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

        SecurityCenter::SecurityFeatures.stubs(
          dependabot_alerts_enabled_for_instance?: true,
          code_scanning_enabled_for_instance?: true,
          secret_scanning_enabled_for_instance?: true,
        )
      end

      context "#perform" do
        test "it works" do
          create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

          result = new_query.perform

          assert_same_elements %i[dependabot_alerts code_scanning secret_scanning], result.keys
          assert_equal 1, result[:dependabot_alerts]
          assert_equal 2, result[:code_scanning]
          assert_equal 3, result[:secret_scanning]
        end

        test "it handles no repos" do
          result = new_query.perform

          assert_same_elements %i[dependabot_alerts code_scanning secret_scanning], result.keys
          assert_equal 0, result[:dependabot_alerts]
          assert_equal 0, result[:code_scanning]
          assert_equal 0, result[:secret_scanning]
        end

        test "it handles archived repos" do
          create_repo(archived: false, dbot_count: 1, cs_count: 2, ss_count: 3)
          create_repo(archived: true, dbot_count: 1, cs_count: 2, ss_count: 3)
          create_repo(archived: true, dbot_count: 1, cs_count: 2, ss_count: 3)

          result = new_query.perform

          assert_same_elements %i[dependabot_alerts code_scanning secret_scanning], result.keys
          assert_equal 1, result[:dependabot_alerts]
        end

        context "filters by accessible repos" do
          test "only dependabot" do
            repo = create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

            repo_ids_by_feature = {
              dependabot_alerts: [repo.id],
              code_scanning: [],
              secret_scanning: [],
            }
            result = new_query(repo_ids_by_feature:).perform

            assert_same_elements %i[dependabot_alerts code_scanning secret_scanning], result.keys
            assert_equal 1, result[:dependabot_alerts]
            assert_equal 0, result[:code_scanning]
            assert_equal 0, result[:secret_scanning]
          end

          test "only code scanning" do
            repo = create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

            repo_ids_by_feature = {
              dependabot_alerts: [],
              code_scanning: [repo.id],
              secret_scanning: [],
            }
            result = new_query(repo_ids_by_feature:).perform

            assert_same_elements %i[dependabot_alerts code_scanning secret_scanning], result.keys
            assert_equal 0, result[:dependabot_alerts]
            assert_equal 2, result[:code_scanning]
            assert_equal 0, result[:secret_scanning]
          end

          test "only secret scanning" do
            repo = create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

            repo_ids_by_feature = {
              dependabot_alerts: [],
              code_scanning: [],
              secret_scanning: [repo.id],
            }
            result = new_query(repo_ids_by_feature:).perform

            assert_same_elements %i[dependabot_alerts code_scanning secret_scanning], result.keys
            assert_equal 0, result[:dependabot_alerts]
            assert_equal 0, result[:code_scanning]
            assert_equal 3, result[:secret_scanning]
          end

          test "no features enabled" do
            create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

            repo_ids_by_feature = {
              dependabot_alerts: [],
              code_scanning: [],
              secret_scanning: [],
            }
            result = new_query(repo_ids_by_feature:).perform

            assert_same_elements %i[dependabot_alerts code_scanning secret_scanning], result.keys
            assert_equal 0, result[:dependabot_alerts]
            assert_equal 0, result[:code_scanning]
            assert_equal 0, result[:secret_scanning]
          end
        end

        context "filters by enabled features" do
          test "only dependabot" do
            SecurityCenter::SecurityFeatures.stubs(
              dependabot_alerts_enabled_for_instance?: true,
              code_scanning_enabled_for_instance?: false,
              secret_scanning_enabled_for_instance?: false,
            )

            create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

            result = new_query.perform

            assert_same_elements %i[dependabot_alerts], result.keys
            assert_equal 1, result[:dependabot_alerts]
          end

          test "only code scanning" do
            SecurityCenter::SecurityFeatures.stubs(
              dependabot_alerts_enabled_for_instance?: false,
              code_scanning_enabled_for_instance?: true,
              secret_scanning_enabled_for_instance?: false,
            )

            create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

            result = new_query.perform

            assert_same_elements %i[code_scanning], result.keys
            assert_equal 2, result[:code_scanning]
          end

          test "only secret scanning" do
            SecurityCenter::SecurityFeatures.stubs(
              dependabot_alerts_enabled_for_instance?: false,
              code_scanning_enabled_for_instance?: false,
              secret_scanning_enabled_for_instance?: true,
            )

            create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

            result = new_query.perform

            assert_same_elements %i[secret_scanning], result.keys
            assert_equal 3, result[:secret_scanning]
          end

          test "no features enabled" do
            SecurityCenter::SecurityFeatures.stubs(
              dependabot_alerts_enabled_for_instance?: false,
              code_scanning_enabled_for_instance?: false,
              secret_scanning_enabled_for_instance?: false,
            )

            create_repo(dbot_count: 1, cs_count: 2, ss_count: 3)

            result = new_query.perform

            assert_empty result.keys
          end
        end
      end

      private

      def new_query(scope: @org, user: @org_owner, user_session: @org_owner_session, repo_ids_by_feature: nil)
        TabCountsQuery.for_organization(
          organization: scope,
          user:,
          user_session:,
          repo_ids_by_feature:,
          parser: Search::Queries::SecurityCenter::RiskQueryParser.new(""),
        )
      end

      def create_repo(
        owner: @org,
        archived: false,
        dbot_count: 0,
        cs_count: 0,
        ss_count: 0
      )
        create(:private_repository, owner:).tap do |repository|
          repository.set_archived if archived

          repository_metadata = create(:soa_repository, repository:)
          create(
            :soa_feature_status,
            repository_metadata:,
            dependabot_alerts_total_count: dbot_count,
            code_scanning_alerts_total_count: cs_count,
            secret_scanning_alerts_total_count: ss_count,
          )
        end
      end
    end
  end
end
