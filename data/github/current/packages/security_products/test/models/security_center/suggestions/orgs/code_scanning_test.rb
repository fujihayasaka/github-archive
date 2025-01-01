# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Orgs
      class CodeScanningTest < GitHub::TestCase
        fixtures do
          @org_admin = create(:user, name: "org-admin")
          @user_session = create(:user_session, user: @org_admin)
          @org = create(:organization, login: "test-org", admin: @org_admin)
          @repo = create(:repository, owner: @org, name: "test-repo")
        end

        context "when use for CodeQL Rule" do
          test "it returns an empty array if authorized orgs is empty" do
            ::CodeScanning::AlertQueryService.any_instance.expects(:rules_for_org).never

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::CodeQLRule,
              allowed_repo_ids: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all authorized orgs and users" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:tools][0] == "CodeQL" &&
                request[:filter][:severities] == [:SEVERITY_CRITICAL, :SEVERITY_HIGH, :SEVERITY_MEDIUM, :SEVERITY_LOW]
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::CodeQLRule,
              allowed_repo_ids: [@repo.id]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              ),
              Suggestion.new(
                label: "test rule 1",
                value: "test/test1",
                description: "test/test1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions omitting the selected values" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:tools][0] == "CodeQL" &&
                request[:filter][:severities] == [:SEVERITY_CRITICAL, :SEVERITY_HIGH, :SEVERITY_MEDIUM, :SEVERITY_LOW]
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::CodeQLRule,
              allowed_repo_ids: [@repo.id],
              selected_values: ["TEST/TEST2"]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 1",
                value: "test/test1",
                description: "test/test1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions matching the value" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:tools][0] == "CodeQL" &&
                request[:filter][:severities] == [:SEVERITY_CRITICAL, :SEVERITY_HIGH, :SEVERITY_MEDIUM, :SEVERITY_LOW]
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::CodeQLRule,
              allowed_repo_ids: [@repo.id],
              value: "TEST2"
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it limits the number of suggestions returned" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:tools][0] == "CodeQL" &&
                request[:filter][:severities] == [:SEVERITY_CRITICAL, :SEVERITY_HIGH, :SEVERITY_MEDIUM, :SEVERITY_LOW]
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::CodeQLRule,
              allowed_repo_ids: [@repo.id],
              limit: 1
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        context "when use for Third-party Rule" do
          test "it returns an empty array if authorized orgs is empty" do
            ::CodeScanning::AlertQueryService.any_instance.expects(:rules_for_org).never

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::ThirdPartyRule,
              allowed_repo_ids: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all authorized orgs and users" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:excluded_tools][0] == "CodeQL" &&
                request[:filter][:severities] == [:SEVERITY_CRITICAL, :SEVERITY_HIGH, :SEVERITY_MEDIUM, :SEVERITY_LOW]
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::ThirdPartyRule,
              allowed_repo_ids: [@repo.id]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              ),
              Suggestion.new(
                label: "test rule 1",
                value: "test/test1",
                description: "test/test1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions omitting the selected values" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:excluded_tools][0] == "CodeQL"
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::ThirdPartyRule,
              allowed_repo_ids: [@repo.id],
              selected_values: ["TEST/TEST2"]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 1",
                value: "test/test1",
                description: "test/test1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions matching the value" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:excluded_tools][0] == "CodeQL"
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::ThirdPartyRule,
              allowed_repo_ids: [@repo.id],
              value: "TEST2"
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it limits the number of suggestions returned" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:excluded_tools][0] == "CodeQL"
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::ThirdPartyRule,
              allowed_repo_ids: [@repo.id],
              limit: 1
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        context "when use for All Rule" do
          test "it returns an empty array if authorized orgs is empty" do
            ::CodeScanning::AlertQueryService.any_instance.expects(:rules_for_org).never

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::AllRule,
              allowed_repo_ids: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all authorized orgs and users" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:tools].empty? && request[:filter][:excluded_tools].empty? && request[:filter][:severities].empty?
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::AllRule,
              allowed_repo_ids: [@repo.id]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              ),
              Suggestion.new(
                label: "test rule 1",
                value: "test/test1",
                description: "test/test1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions omitting the selected values" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:tools].empty? && request[:filter][:excluded_tools].empty? && request[:filter][:severities].empty?
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::AllRule,
              allowed_repo_ids: [@repo.id],
              selected_values: ["TEST/TEST2"]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 1",
                value: "test/test1",
                description: "test/test1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions matching the value" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:tools].empty? && request[:filter][:excluded_tools].empty? && request[:filter][:severities].empty?
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::AllRule,
              allowed_repo_ids: [@repo.id],
              value: "TEST2"
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it limits the number of suggestions returned" do
            GitHub::Turboscan
              .expects(:rules_for_org)
              .with do |request|
                request[:filter][:tools].empty? && request[:filter][:excluded_tools].empty? && request[:filter][:severities].empty?
              end
              .once
              .returns(get_rules_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::AllRule,
              allowed_repo_ids: [@repo.id],
              limit: 1
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test rule 2",
                value: "test/test2",
                description: "test/test2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        context "when use for Tools" do
          test "it returns an empty array if authorized orgs is empty" do
            ::CodeScanning::AlertQueryService.any_instance.expects(:tool_names_for_org).never

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::Tool,
              allowed_repo_ids: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all authorized orgs and users" do
            GitHub::Turboscan
              .expects(:tool_names_for_org)
              .once
              .returns(get_tool_names_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::Tool,
              allowed_repo_ids: [@repo.id]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test tool 2",
                value: "test tool 2",
                description: "test tool 2"
              ),
              Suggestion.new(
                label: "test tool 1",
                value: "test tool 1",
                description: "test tool 1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions omitting the selected values" do
            GitHub::Turboscan
              .expects(:tool_names_for_org)
              .once
              .returns(get_tool_names_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::Tool,
              allowed_repo_ids: [@repo.id],
              selected_values: ["test tool 2"]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test tool 1",
                value: "test tool 1",
                description: "test tool 1"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions matching the value" do
            GitHub::Turboscan
              .expects(:tool_names_for_org)
              .once
              .returns(get_tool_names_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::Tool,
              allowed_repo_ids: [@repo.id],
              value: "tool 2"
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test tool 2",
                value: "test tool 2",
                description: "test tool 2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it limits the number of suggestions returned" do
            GitHub::Turboscan
              .expects(:tool_names_for_org)
              .once
              .returns(get_tool_names_for_org_response)

            suggestions = CodeScanning.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: CodeScanning::FilterType::Tool,
              allowed_repo_ids: [@repo.id],
              limit: 1
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "test tool 2",
                value: "test tool 2",
                description: "test tool 2"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        private

        def get_rules_for_org_response
          Twirp::ClientResp.new(
            data: Turboscan::Proto::RulesForOrgResponse.new(
              rules: [
                Turboscan::Proto::OrgRule.new(
                  alert_count: 1,
                  sarif_identifier: "test/test2",
                  short_description: "test rule 2"
                ),
                Turboscan::Proto::OrgRule.new(
                  alert_count: 1,
                  sarif_identifier: "test/test1",
                  short_description: "test rule 1"
                )
              ]
            )
          )
        end

        def get_tool_names_for_org_response
          Twirp::ClientResp.new(
            data: Turboscan::Proto::ToolNamesResponse.new(
              tools: [
                Turboscan::Proto::ToolDescription.new(
                  alert_count: 1,
                  name: "test tool 2"
                ),
                Turboscan::Proto::ToolDescription.new(
                  alert_count: 1,
                  name: "test tool 1"
                )
              ]
            )
          )
        end
      end
    end
  end
end
