# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Businesses
      class DependabotTest < GitHub::TestCase
        fixtures do
          @org_admin = create(:user, name: "org-admin")
          @user_session = create(:user_session, user: @org_admin)
          @business = create(:global_business)
          @org = create(:organization, business: @business, login: "test-org", admin: @org_admin)
          @repo = create(:repository, owner: @org, name: "test-repo")

          create(:repository_security_center_config, repository: @repo)
          create(:repository_security_center_status, :dependabot_alerts, :enrolled, repository: @repo, scanning_count: 3)
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
          test "it returns an empty array if authorized orgs is empty" do
            ::RepositoryVulnerabilityAlert::UngroupedAlertQuery.any_instance.expects(:ecosystem_filter_options).never

            suggestions = Dependabot.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              authorized_orgs: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all authorized orgs and users" do
            suggestions = Dependabot.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              authorized_orgs: [@org]
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
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              authorized_orgs: [@org],
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
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              authorized_orgs: [@org],
              value: "gem"
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
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Ecosystem,
              authorized_orgs: [@org],
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
          test "it returns an empty array if authorized orgs is empty" do
            ::RepositoryVulnerabilityAlert::UngroupedAlertQuery.any_instance.expects(:package_filter_options).never

            suggestions = Dependabot.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              authorized_orgs: []
            ).suggestions

            assert_same_elements([], suggestions)
          end

          test "it returns suggestions for all authorized orgs and users" do
            suggestions = Dependabot.new(
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              authorized_orgs: [@org]
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
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              authorized_orgs: [@org],
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
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              authorized_orgs: [@org],
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
              business: @business,
              user: @org_admin,
              user_session: @user_session,
              type: Dependabot::FilterType::Package,
              authorized_orgs: [@org],
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
