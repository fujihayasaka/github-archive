# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotEnterpriseTest < GitHub::TestCase
  context "initialize" do
    context "compliant business" do
      test "it returns no commits, issues, pull requests or repositories" do
        business = FactoryBot.create(:copilot_for_enterprise_business, :with_azure_subscription)
        organization = create(
          :enterprise_linked_organization,
          business: business,
        )

        assert_equal business, organization.business

        copilot_business = Copilot::Business.new(business)
        copilot_business.enable_copilot_for_all_organizations!

        enterprise = Copilot::CopilotEnterprise.new(copilot_business)

        assert_equal business.customer.azure_subscription_id, enterprise.azure_subscription

        assert_equal 0, enterprise.commit_count
        assert_equal 0, enterprise.copilot_seat_count
        assert_equal 0, enterprise.issue_count
        assert_equal 1, enterprise.organization_count
        assert_equal 0, enterprise.pull_request_count
        assert_equal 0, enterprise.repository_count
      end
    end

    context "with commits" do
      test "it returns no commits for empty repository" do
        business = FactoryBot.create(:copilot_for_enterprise_business, :with_azure_subscription)
        organization = create(
          :enterprise_linked_organization,
          business: business,
        )

        assert_equal business, organization.business
        create(:repository, owner: organization)

        copilot_business = Copilot::Business.new(business)
        copilot_business.enable_copilot_for_all_organizations!

        enterprise = Copilot::CopilotEnterprise.new(copilot_business)

        assert_equal business.customer.azure_subscription_id, enterprise.azure_subscription

        assert_equal 0, enterprise.commit_count
        assert_equal 0, enterprise.copilot_seat_count
        assert_equal 0, enterprise.issue_count
        assert_equal 1, enterprise.organization_count
        assert_equal 0, enterprise.pull_request_count
        assert_equal 1, enterprise.repository_count
      end

      test "it returns 5 commits for example repository" do
        business = FactoryBot.create(:copilot_for_enterprise_business, :with_azure_subscription)
        organization = create(
          :enterprise_linked_organization,
          business: business,
        )

        assert_equal business, organization.business
        create(:repository, owner: organization, from_example: :simple_default_main) # this has 5 refs

        copilot_business = Copilot::Business.new(business)
        copilot_business.enable_copilot_for_all_organizations!

        enterprise = Copilot::CopilotEnterprise.new(copilot_business)

        assert_equal business.customer.azure_subscription_id, enterprise.azure_subscription

        assert_equal 5, enterprise.commit_count
        assert_equal 0, enterprise.copilot_seat_count
        assert_equal 0, enterprise.issue_count
        assert_equal 1, enterprise.organization_count
        assert_equal 0, enterprise.pull_request_count
        assert_equal 1, enterprise.repository_count
      end
    end

    context "with copilot seats" do
      test "it gets correct number of copilot seats" do
        users = create_list(:user, 3)
        business = create(:copilot_for_enterprise_business, :with_azure_subscription)
        business.add_user_accounts(users)
        organization = create(
          :enterprise_linked_organization,
          business: business,
        )
        organization.bulk_add_members(users)

        assert_equal business, organization.business

        copilot_business = Copilot::Business.new(business)
        copilot_business.enable_copilot_for_all_organizations!

        seat_assignment = create(:copilot_seat_assignment, assignable: organization, organization: organization, assigning_user: organization.admins.first)
        seat_assignment.convert_to_seats

        enterprise = Copilot::CopilotEnterprise.new(copilot_business)
        assert_equal business.customer.azure_subscription_id, enterprise.azure_subscription
        assert_equal 0, enterprise.commit_count
        assert_equal 4, enterprise.copilot_seat_count
        assert_equal 0, enterprise.issue_count
        assert_equal 1, enterprise.organization_count
        assert_equal 0, enterprise.pull_request_count
        assert_equal 0, enterprise.repository_count
      end
    end

    context "with issues" do
      test "it returns 1 issue for example repository" do
        business = FactoryBot.create(:copilot_for_enterprise_business, :with_azure_subscription)
        organization = create(
          :enterprise_linked_organization,
          business: business,
        )

        assert_equal business, organization.business
        repo = create(:repository, owner: organization, from_example: :simple_default_main) # this has 5 refs
        create(:issue, repository: repo)
        copilot_business = Copilot::Business.new(business)
        copilot_business.enable_copilot_for_all_organizations!

        enterprise = Copilot::CopilotEnterprise.new(copilot_business)

        assert_equal business.customer.azure_subscription_id, enterprise.azure_subscription

        assert_equal 5, enterprise.commit_count
        assert_equal 0, enterprise.copilot_seat_count
        assert_equal 1, enterprise.issue_count
        assert_equal 1, enterprise.organization_count
        assert_equal 0, enterprise.pull_request_count
        assert_equal 1, enterprise.repository_count
      end
    end

    context "with pull requests" do
      test "it returns 1 pull for example repository" do
        business = FactoryBot.create(:copilot_for_enterprise_business, :with_azure_subscription)
        organization = create(
          :enterprise_linked_organization,
          business: business,
        )

        assert_equal business, organization.business
        repo = create(:repository, from_example: :pull_request_source, owner: organization)
        create(:pull_request, repository: repo, base_repository: repo, head_repository: repo, head_ref: "master-merged-topic")

        copilot_business = Copilot::Business.new(business)
        copilot_business.enable_copilot_for_all_organizations!

        enterprise = Copilot::CopilotEnterprise.new(copilot_business)

        assert_equal business.customer.azure_subscription_id, enterprise.azure_subscription

        assert_equal 7, enterprise.commit_count
        assert_equal 0, enterprise.copilot_seat_count
        assert_equal 1, enterprise.issue_count # 1 issue for the pull request
        assert_equal 1, enterprise.organization_count
        assert_equal 1, enterprise.pull_request_count
        assert_equal 1, enterprise.repository_count
      end
    end

    context "with repositories" do
      test "it a single repositoriy" do
        business = FactoryBot.create(:copilot_for_enterprise_business, :with_azure_subscription)
        organization = create(
          :enterprise_linked_organization,
          business: business,
        )

        assert_equal business, organization.business
        create(:repository, owner: organization)

        copilot_business = Copilot::Business.new(business)
        copilot_business.enable_copilot_for_all_organizations!

        enterprise = Copilot::CopilotEnterprise.new(copilot_business)

        assert_equal business.customer.azure_subscription_id, enterprise.azure_subscription

        assert_equal 0, enterprise.commit_count
        assert_equal 0, enterprise.copilot_seat_count
        assert_equal 0, enterprise.issue_count
        assert_equal 1, enterprise.organization_count
        assert_equal 0, enterprise.pull_request_count
        assert_equal 1, enterprise.repository_count
      end
    end

    context "with organizations" do
      test "it returns many organizations" do
        business = FactoryBot.create(:copilot_for_enterprise_business, :with_azure_subscription)

        5.times do
          organization = create(
            :enterprise_linked_organization,
            business: business,
          )

          assert_equal business, organization.business
        end

        copilot_business = Copilot::Business.new(business)
        copilot_business.enable_copilot_for_all_organizations!

        enterprise = Copilot::CopilotEnterprise.new(copilot_business)

        assert_equal business.customer.azure_subscription_id, enterprise.azure_subscription

        assert_equal 0, enterprise.commit_count
        assert_equal 0, enterprise.copilot_seat_count
        assert_equal 0, enterprise.issue_count
        assert_equal 5, enterprise.organization_count
        assert_equal 0, enterprise.pull_request_count
        assert_equal 0, enterprise.repository_count
      end
    end
  end
end if GitHub.copilot_enabled?
