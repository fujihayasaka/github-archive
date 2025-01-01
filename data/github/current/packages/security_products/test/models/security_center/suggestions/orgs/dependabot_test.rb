# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Orgs
      class DependabotTest < GitHub::TestCase
        fixtures do
          @org_admin = create(:user, name: "org-admin")
          @user_session = create(:user_session, user: @org_admin)
          @org = create(:organization, login: "test-org", admin: @org_admin)
          @repo = create(:repository, owner: @org, name: "test-repo")

          create(:repository_security_center_config, repository: @repo)
          create(:repository_security_center_status, :dependabot_alerts, :enrolled, repository: @repo)
          create_pair(:repository_vulnerability_alert, :open, {
            repository: @repo,
            affects: "nokogiri", # Package
            ecosystem: "RubyGems", # Ecosystem
          })
          create_pair(:repository_vulnerability_alert, :open, {
            repository: @repo,
            affects: "nokogiri", # Package
            ecosystem: "RubyGems", # Ecosystem
          })
          create_pair(:repository_vulnerability_alert, :open, {
            repository: @repo,
            affects: "lodash",
            ecosystem: "npm",
          })
        end

        context "when use for Ecosystem" do
          test "it returns an empty array if allowed repo ids is empty" do
            ::RepositoryVulnerabilityAlert::UngroupedAlertQuery.any_instance.expects(:ecosystem_filter_options).never

            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              allowed_repo_ids: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all allowed repo ids and users" do
            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              allowed_repo_ids: [@repo.id]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "RubyGems",
                value: "RubyGems",
              ),
              Suggestion.new(
                label: "npm",
                value: "npm",
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions omitting the selected values" do
            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              allowed_repo_ids: [@repo.id],
              selected_values: ["rubygems"]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "npm",
                value: "npm",
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions matching the value" do
            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              allowed_repo_ids: [@repo.id],
              value: "ubyg"
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "RubyGems",
                value: "RubyGems",
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it limits the number of suggestions returned" do
            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              allowed_repo_ids: [@repo.id],
              limit: 1
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "RubyGems",
                value: "RubyGems",
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        context "when use for Package" do
          test "it returns an empty array if allowed repo ids is empty" do
            ::RepositoryVulnerabilityAlert::UngroupedAlertQuery.any_instance.expects(:package_filter_options).never

            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              allowed_repo_ids: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all allowed repo ids and users" do
            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              allowed_repo_ids: [@repo.id]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "nokogiri",
                value: "nokogiri"
              ),
              Suggestion.new(
                label: "lodash",
                value: "lodash"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions omitting the selected values" do
            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              allowed_repo_ids: [@repo.id],
              selected_values: ["noKOGiri"]
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "lodash",
                value: "lodash"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it returns suggestions matching the value" do
            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              allowed_repo_ids: [@repo.id],
              value: "kOGI"
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "nokogiri",
                value: "nokogiri"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end

          test "it limits the number of suggestions returned" do
            suggestions = Dependabot.new(
              organization: @org,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              allowed_repo_ids: [@repo.id],
              limit: 1
            ).suggestions

            expected_suggestions = [
              Suggestion.new(
                label: "nokogiri",
                value: "nokogiri"
              )
            ]

            assert_same_elements(expected_suggestions, suggestions)
          end
        end
      end
    end
  end
end
