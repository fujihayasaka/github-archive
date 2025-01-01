# typed: true
# frozen_string_literal: true

require "test_helper"

class GetRepoSecurityAlertCountsSkillResponseTest < GitHub::TestCase
  include ::SecurityCenter::TestFixtures
  include FineGrainedPermissionsTestHelper

  fixtures do
    create_org_level_fixtures

    @repo_1 = create(:private_repository, name: "repo-1", owner: @org).tap do |r|
      create(:soa_repository, repository: r).tap do |repository_metadata|
        create(
          :soa_feature_status,
          repository_metadata:,
          advanced_security_status: "ENABLED",
          dependabot_alerts_status: "ENABLED",
          dependabot_alerts_total_count: 10,
          dependabot_alerts_critical_count: 10,
          code_scanning_alerts_status: "ENABLED",
          code_scanning_alerts_total_count: 20,
          code_scanning_alerts_high_count: 20,
          secret_scanning_alerts_status: "ENABLED",
          secret_scanning_alerts_total_count: 30,
          dependabot_security_updates_status: "ENABLED",
          dependabot_version_updates_status: "ENABLED",
          code_scanning_pr_reviews_status: "ENABLED",
          code_scanning_auto_codeql_status: "ENABLED",
          secret_scanning_push_protection_status: "ENABLED",
        )
      end

      r.add_member(@member)
    end
    @repo_2 = create(:private_repository, name: "repo-2", owner: @org).tap do |r|
      create(:soa_repository, repository: r).tap do |repository_metadata|
        create(
          :soa_feature_status,
          repository_metadata:,
          advanced_security_status: "ENABLED",
          dependabot_alerts_status: "ENABLED",
          dependabot_alerts_total_count: 20,
          dependabot_alerts_medium_count: 20,
          code_scanning_alerts_status: "ENABLED",
          code_scanning_alerts_total_count: 40,
          code_scanning_alerts_low_count: 40,
          secret_scanning_alerts_status: "ENABLED",
          secret_scanning_alerts_total_count: 60,
          dependabot_security_updates_status: "ENABLED",
          dependabot_version_updates_status: "ENABLED",
          code_scanning_pr_reviews_status: "ENABLED",
          code_scanning_auto_codeql_status: "ENABLED",
          secret_scanning_push_protection_status: "ENABLED",
        )
      end

      r.add_member(@member)
    end
  end

  setup do
    ::Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    ::Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)
    ::SecurityCenter::SecurityFeatures.stubs(
      code_scanning_enabled_for_instance?: true,
      secret_scanning_enabled_for_instance?: true,
      dependabot_alerts_enabled_for_instance?: true
    )

    ::Repository.any_instance.stubs(:can_view_vulnerability_alerts?).returns(true)
    ::Repository.any_instance.stubs(:code_scanning_readable_by?).returns(true)
    ::SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:view_alerts_allowed?).returns(true)
  end

  context "#payload" do
    context "when the user can view all of the repo's security alerts" do
      test "it returns the alert counts for all features" do
        res = ::Copilot::GetRepoSecurityAlertCountsSkillResponse.new(user: @member, repo: @repo_1).payload

        expected_res = {
          code_scanning: {
            alert_counts: {
              critical: 0,
              high: 20,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Code scanning alerts",
            sub_features: {
              pull_request_reviews: {
                enablement_status: "enrolled",
                name: "Code scanning pull request alerts"
              },
              codeql_default_setup: {
                enablement_status: "enrolled",
                name: "CodeQL default setup"
              }
            },
          },
          dependabot: {
            alert_counts: {
              critical: 10,
              high: 0,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Dependabot alerts",
            sub_features: {
              security_updates: { enablement_status: "enrolled", name: "Dependabot security updates" },
              version_updates: nil,
            }
          },
          repo_id: @repo_1.id,
          secret_scanning: {
            alert_counts: {
              critical: 30,
              high: 0,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Secret scanning alerts",
            sub_features: {
              push_protection: {
                enablement_status: "enrolled",
                name: "Secret scanning push protection"
              }
            }
          }
        }

        assert_equal(expected_res, res.to_h)
      end
    end

    context "when the user cannot view the repo's code scanning alerts" do
      test "it returns the alert counts without code scanning" do
        ::Repository.any_instance.stubs(:code_scanning_readable_by?).returns(false)

        res = ::Copilot::GetRepoSecurityAlertCountsSkillResponse.new(user: @member, repo: @repo_1).payload

        expected_res = {
          code_scanning: nil,
          dependabot: {
            alert_counts: {
              critical: 10,
              high: 0,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Dependabot alerts",
            sub_features: {
              security_updates: { enablement_status: "enrolled", name: "Dependabot security updates" },
              version_updates: nil,
            }
          },
          repo_id: @repo_1.id,
          secret_scanning: {
            alert_counts: {
              critical: 30,
              high: 0,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Secret scanning alerts",
            sub_features: {
              push_protection: {
                enablement_status: "enrolled",
                name: "Secret scanning push protection"
              }
            }
          }
        }

        assert_equal(expected_res, res.to_h)
      end
    end

    context "when the user cannot view the repo's Dependabot alerts" do
      test "it returns the alert counts without Dependabot" do
        ::Repository.any_instance.stubs(:can_view_vulnerability_alerts?).returns(false)

        res = ::Copilot::GetRepoSecurityAlertCountsSkillResponse.new(user: @member, repo: @repo_1).payload

        expected_res = {
          code_scanning: {
            alert_counts: {
              critical: 0,
              high: 20,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Code scanning alerts",
            sub_features: {
              pull_request_reviews: {
                enablement_status: "enrolled",
                name: "Code scanning pull request alerts"
              },
              codeql_default_setup: {
                enablement_status: "enrolled",
                name: "CodeQL default setup"
              }
            },
          },
          dependabot: nil,
          repo_id: @repo_1.id,
          secret_scanning: {
            alert_counts: {
              critical: 30,
              high: 0,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Secret scanning alerts",
            sub_features: {
              push_protection: {
                enablement_status: "enrolled",
                name: "Secret scanning push protection"
              }
            }
          }
        }

        assert_equal(expected_res, res.to_h)
      end
    end

    context "when the user cannot view the repo's Secret Scanning alerts" do
      test "it returns the alert counts without Secret Scanning" do
        ::SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:view_alerts_allowed?).returns(false)

        res = ::Copilot::GetRepoSecurityAlertCountsSkillResponse.new(user: @member, repo: @repo_1).payload

        expected_res = {
          code_scanning: {
            alert_counts: {
              critical: 0,
              high: 20,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Code scanning alerts",
            sub_features: {
              pull_request_reviews: {
                enablement_status: "enrolled",
                name: "Code scanning pull request alerts"
              },
              codeql_default_setup: {
                enablement_status: "enrolled",
                name: "CodeQL default setup"
              }
            },
          },
          dependabot: {
            alert_counts: {
              critical: 10,
              high: 0,
              informational: 0,
              low: 0,
              medium: 0
            },
            enablement_status: "enrolled",
            name: "Dependabot alerts",
            sub_features: {
              security_updates: { enablement_status: "enrolled", name: "Dependabot security updates" },
              version_updates: nil,
            }
          },
          repo_id: @repo_1.id,
          secret_scanning: nil
        }

        assert_equal(expected_res, res.to_h)
      end
    end

    context "when the user cannot view any of repo's security alerts" do
      test "it returns an empty response" do
        ::Repository.any_instance.stubs(:code_scanning_readable_by?).returns(false)
        ::Repository.any_instance.stubs(:can_view_vulnerability_alerts?).returns(false)
        ::SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:view_alerts_allowed?).returns(false)

        res = ::Copilot::GetRepoSecurityAlertCountsSkillResponse.new(user: @member, repo: @repo_1).payload

        expected_res = {
          code_scanning: nil,
          dependabot: nil,
          repo_id: @repo_1.id,
          secret_scanning: nil
        }

        assert_equal(expected_res, res.to_h)
      end
    end
  end
end
