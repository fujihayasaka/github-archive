# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Businesses
      class SecretScanningTest < GitHub::TestCase
        fixtures do
          @business = create(:global_business)
          @org = create(:organization, business: @business, login: "test-org", admin: @org_admin)
          @org_admin = create(:user, name: "org-admin")
          @user_session = create(:user_session, user: @org_admin)
        end

        context "when use for SecretType" do
          test "it returns an empty array if authorized orgs is empty" do
            ::SecretScanning::AlertQueryService.any_instance.expects(:get_filter_options).never

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::SecretType,
              authorized_orgs: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all authorized orgs and users" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token_group_by_counts)
              .once
              .returns(get_token_group_by_counts_response)

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::SecretType,
              authorized_orgs: [@org]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "type_label_1",
                value: "type_slug_1",
                description: "type_slug_1"
              ),
              Suggestion.new(
                label: "type_label_2",
                value: "type_slug_2",
                description: "type_slug_2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions omitting the selected values" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token_group_by_counts)
              .once
              .returns(get_token_group_by_counts_response)

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::SecretType,
              authorized_orgs: [@org],
              selected_values: ["TYPE_SLUG_1"]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "type_label_2",
                value: "type_slug_2",
                description: "type_slug_2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions matching the value" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token_group_by_counts)
              .once
              .returns(get_token_group_by_counts_response)

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::SecretType,
              authorized_orgs: [@org],
              value: "SLUG_1"
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "type_label_1",
                value: "type_slug_1",
                description: "type_slug_1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it limits the number of suggestions returned" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token_group_by_counts)
              .once
              .returns(get_token_group_by_counts_response)

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::SecretType,
              authorized_orgs: [@org],
              limit: 1
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "type_label_1",
                value: "type_slug_1",
                description: "type_slug_1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        context "when use for Provider" do
          test "it returns an empty array if authorized orgs is empty" do
            ::SecretScanning::AlertQueryService.any_instance.expects(:get_filter_options).never

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::Provider,
              authorized_orgs: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all authorized orgs and users" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token_group_by_counts)
              .once
              .returns(get_token_group_by_counts_response)

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::Provider,
              authorized_orgs: [@org]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "AWS",
                value: "aws",
                description: "aws"
              ),
              Suggestion.new(
                label: "GitHub Secret Scanning",
                value: "github_secret_scanning",
                description: "github_secret_scanning"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions omitting the selected values" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token_group_by_counts)
              .once
              .returns(get_token_group_by_counts_response)

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::Provider,
              authorized_orgs: [@org],
              selected_values: ["AWS"]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "GitHub Secret Scanning",
                value: "github_secret_scanning",
                description: "github_secret_scanning"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions matching the value" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token_group_by_counts)
              .once
              .returns(get_token_group_by_counts_response)

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::Provider,
              authorized_orgs: [@org],
              value: "AWS"
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "AWS",
                value: "aws",
                description: "aws"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it limits the number of suggestions returned" do
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token_group_by_counts)
              .once
              .returns(get_token_group_by_counts_response)

            suggestions = SecretScanning.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: SecretScanning::FilterType::Provider,
              authorized_orgs: [@org],
              limit: 1
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "AWS",
                value: "aws",
                description: "aws"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        private

        def get_token_group_by_counts_response
          Twirp::ClientResp.new(
            data: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse.new(
              counts: [
                GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount.new(
                  provider_aggregation: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation.new(
                    counts: [
                      GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation::ProviderCount.new(
                        provider_name: "GitHub Secret Scanning",
                        unresolved_count: 1,
                        resolved_count: 2
                      ),
                      GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation::ProviderCount.new(
                        provider_name: "AWS",
                        unresolved_count: 44,
                        resolved_count: 55
                      ),
                    ]
                  )
                ),
                GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount.new(
                  type_aggregation: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation.new(
                    counts: [
                      GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation::TypeCount.new(
                        type: GitHub::Proto::SecretScanning::Api::V2::TokenType.new(
                          type_value:  "type_1",
                          label_value: "type_label_1",
                          slug_value:  "type_slug_1",
                        ),
                        unresolved_count: 6,
                        resolved_count: 7
                      ),
                      GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation::TypeCount.new(
                        type: GitHub::Proto::SecretScanning::Api::V2::TokenType.new(
                          type_value:  "type_1_v2",
                          label_value: "type_label_1",
                          slug_value:  "type_slug_1",
                        ),
                        unresolved_count: 66,
                        resolved_count: 77
                      ),
                      GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation::TypeCount.new(
                        type: GitHub::Proto::SecretScanning::Api::V2::TokenType.new(
                          type_value:  "type_2",
                          label_value: "type_label_2",
                          slug_value:  "type_slug_2",
                        ),
                        unresolved_count: 2,
                        resolved_count: 3
                      )
                    ]
                  )
                )
              ]
            )
          )
        end
      end
    end
  end
end
