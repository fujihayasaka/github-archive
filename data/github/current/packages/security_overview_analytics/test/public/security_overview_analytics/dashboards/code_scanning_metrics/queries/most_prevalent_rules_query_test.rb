# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class MostPrevalentRulesQueryTest < GitHub::TestCase
          include SecurityCenter::TestFixtures
          include ::SecurityOverviewAnalytics::TestFixtures

          fixtures do
            create_business_level_fixtures

            date_id = 20240801
            date = Date.find_by(id: date_id) || create(:soa_date, date_value: ::Date.parse(date_id.to_s))

            [
              @org1_private_repo = create(:private_repository, owner: @org),
              @org1_public_repo = create(:public_repository, owner: @org),
              @org2_private_repo = create(:private_repository, owner: @org2),
              @org2_public_repo = create(:public_repository, owner: @org2),
            ].each do |repository|
              repository_metadata = create(:soa_repository, repository:)
              create(:soa_feature_status_revision, repository_metadata:, date:, code_scanning_enabled: true)

              # Enough distinct rules to require pagination
              15.times.each do |rule_idx|
                scenario = { rule_sarif_identifier: "rule/#{rule_idx}" }

                (rule_idx + 1).times do |alert_idx|
                  # We create a number of alerts for the rule's index in the above list.
                  # This makes sure we have variation in test data to validate grouping.
                  create(
                    :soa_code_scanning_pr_alert,
                    repository_metadata:,
                    alert_number: 100 * rule_idx + alert_idx,
                    date_id:,
                    **scenario,
                  )
                end
              end
            end
          end

          setup do
            Timecop.freeze do
              @default_end_date = ::Date.parse("2024-08-14")
              @default_start_date = @default_end_date - 30.days
            end

            GitHub::Turboscan.stubs(:alert_titles)
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::AlertTitlesResponse.new(
                    repository_ids: CodeScanningPullRequestAlert.pluck(:repository_id),
                    alert_numbers: CodeScanningPullRequestAlert.pluck(:alert_number),
                    titles: \
                      CodeScanningPullRequestAlert.pluck(:rule_sarif_identifier).map do |rule_sarif_identifier|
                        m = rule_sarif_identifier.match /rule\/(?<rule_idx>\d+)/
                        "Rule name #{m[:rule_idx]}"
                      end,
                  )
                )
              )
          end

          context ".for_business" do
            context "#perform" do
              test "it works" do
                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_items(actual.items, {
                  14 => 60,
                  13 => 56,
                  12 => 52,
                  11 => 48,
                  10 => 44,
                  9 => 40,
                  8 => 36,
                  7 => 32,
                  6 => 28,
                  5 => 24,
                })
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it filters to authorized organizations" do
                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: [@org],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_items(actual.items, {
                  14 => 30,
                  13 => 28,
                  12 => 26,
                  11 => 24,
                  10 => 22,
                  9 => 20,
                  8 => 18,
                  7 => 16,
                  6 => 14,
                  5 => 12,
                })
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it returns no data when no authorized organizations" do
                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: [],
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_empty actual.items
                assert_nil actual.previous
                assert_nil actual.next
              end

              test "it applies repo filters" do
                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_items(actual.items, {
                  14 => 30,
                  13 => 28,
                  12 => 26,
                  11 => 24,
                  10 => 22,
                  9 => 20,
                  8 => 18,
                  7 => 16,
                  6 => 14,
                  5 => 12,
                })
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it applies alert filters" do
                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_items(actual.items, {
                  14 => 60,
                  13 => 56,
                  12 => 52,
                  11 => 48,
                  10 => 44,
                  9 => 40,
                  8 => 36,
                  7 => 32,
                  6 => 28,
                  5 => 24,
                })
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it handles pagination" do
                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "4",
                  page_size: 2,
                )

                refute_nil actual
                assert_items(actual.items, {
                  10 => 44,
                  9 => 40,
                })
                assert_equal "2", actual.previous
                assert_equal "6", actual.next
              end
            end
          end

          context ".for_organization" do
            context "#perform" do
              test "it works" do
                sut = MostPrevalentRulesQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_items(actual.items, {
                  14 => 30,
                  13 => 28,
                  12 => 26,
                  11 => 24,
                  10 => 22,
                  9 => 20,
                  8 => 18,
                  7 => 16,
                  6 => 14,
                  5 => 12,
                })
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it filters to accessible repositories" do
                sut = MostPrevalentRulesQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [@org1_private_repo],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_items(actual.items, {
                  14 => 15,
                  13 => 14,
                  12 => 13,
                  11 => 12,
                  10 => 11,
                  9 => 10,
                  8 => 9,
                  7 => 8,
                  6 => 7,
                  5 => 6,
                })
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it returns no data when no allowed repositories" do
                sut = MostPrevalentRulesQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: [],
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_empty actual.items
                assert_nil actual.previous
                assert_nil actual.next
              end

              test "it applies repo filters" do
                sut = MostPrevalentRulesQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("visibility:private"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_items(actual.items, {
                  14 => 15,
                  13 => 14,
                  12 => 13,
                  11 => 12,
                  10 => 11,
                  9 => 10,
                  8 => 9,
                  7 => 8,
                  6 => 7,
                  5 => 6,
                })
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it applies alert filters" do
                sut = MostPrevalentRulesQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new("severity:critical"),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual
                assert_items(actual.items, {
                  14 => 30,
                  13 => 28,
                  12 => 26,
                  11 => 24,
                  10 => 22,
                  9 => 20,
                  8 => 18,
                  7 => 16,
                  6 => 14,
                  5 => 12,
                })
                assert_nil actual.previous
                assert_equal "10", actual.next
              end

              test "it handles pagination" do
                sut = MostPrevalentRulesQuery.for_organization(
                  organization: @org,
                  allowed_repo_ids: nil,
                  user: @orgs_owner,
                  user_session: @orgs_owner_user_session,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "4",
                  page_size: 2,
                )

                refute_nil actual
                assert_items(actual.items, {
                  10 => 22,
                  9 => 20,
                })
                assert_equal "2", actual.previous
                assert_equal "6", actual.next
              end
            end
          end

          context "resiliency" do
            context "when turboscan has a connection error" do
              test "it includes default rule name" do
                # When the turboscan client has a failure (Faraday etc)
                # they swallow it and return nil
                GitHub::Turboscan.stubs(:alert_titles)
                  .returns(nil)

                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual.items
                actual.items.each do |item|
                  assert_equal "Unknown rule", item.ruleName
                end
              end
            end

            context "when turboscan returns an internal error" do
              test "it includes default rule name" do
                # If turboscan has an internal error, the twirp error comes through
                GitHub::Turboscan.stubs(:alert_titles)
                  .returns(
                    Twirp::ClientResp.new(
                      data: nil,
                      error: Twirp::Error.new(:unavailable, "unavailable"),
                    )
                  )

                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual.items
                actual.items.each do |item|
                  assert_equal "Unknown rule", item.ruleName
                end
              end
            end

            context "when turboscan result does not include expected rule" do
              test "it includes default rule name" do
                GitHub::Turboscan.stubs(:alert_titles)
                  .returns(
                    Twirp::ClientResp.new(
                      data: Turboscan::Proto::AlertTitlesResponse.new(
                        repository_ids: [],
                        alert_numbers: [],
                        titles: [],
                      )
                    )
                  )

                sut = MostPrevalentRulesQuery.for_business(
                  business: @business,
                  organizations: @business.organizations.to_a,
                  user: @orgs_owner,
                  query: Search::Queries::SecurityCenter::QueryParser.new(""),
                  start_date: @default_start_date,
                  end_date: @default_end_date,
                )

                actual = sut.perform(
                  cursor: "0",
                  page_size: 10,
                )

                refute_nil actual.items
                actual.items.each do |item|
                  assert_equal "Unknown rule", item.ruleName
                end
              end
            end
          end

          private

          sig do
            params(
              items: T::Array[MostPrevalentRulesQuery::ListItem],
              expectations: T::Hash[Integer, Integer],
            ).void
          end
          def assert_items(items, expectations)
            refute_nil items
            refute_nil expectations

            expectations.each_with_index do |(rule_idx, count), item_idx|
              refute_nil items[item_idx]

              assert_equal "rule/#{rule_idx}", items[item_idx]&.ruleSarifIdentifier
              assert_equal "Rule name #{rule_idx}", items[item_idx]&.ruleName
              assert_equal count, items[item_idx]&.count
            end

            assert_equal expectations.length, items.length
          end
        end
      end
    end
  end
end
