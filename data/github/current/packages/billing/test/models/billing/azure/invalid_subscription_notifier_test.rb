# typed: true
# frozen_string_literal: true

require "test_helper"
require "digest"

class Billing::Azure::InvalidSubscriptionNotifierTest < GitHub::TestCase
  setup do
    @business = create(:business, :with_azure_subscription)
  end

  context "#notify" do
    test "opens an issue on the sales-operations repo for an enterprise" do
      github_organization = create(:organization, login: "github")
      sales_operations_repository = create(:repository, owner: github_organization, name: "sales-operations")
      enterprise_account_setup_label = create(:label, repository: sales_operations_repository, name: "Enterprise Account Set-up")
      sales_support_label = create(:label, repository: sales_operations_repository, name: "sales-support")
      subscription_digest = Digest::SHA256.hexdigest(@business.customer.azure_subscription_id)[0..12]

      Billing::Azure::InvalidSubscriptionNotifier.new.notify(business: @business)

      assert_equal 1, sales_operations_repository.issues.count
      issue = sales_operations_repository.issues.first

      assert_equal "Azure Subscription ID is invalid for #{@business.name}, #{subscription_digest}", issue.title
      assert_match(/check for Azure Subsription ID status failed at/, issue.body)
      assert_match(/Enterprise/, issue.body)
      assert_match(/_Please have their sales rep reach out to get this rectified/, issue.body)
      assert_match(/Terms of Service Notes/, issue.body)
      assert_match(/Stafftools/, issue.body)
      assert_match(/Reach out to the account contact at/, issue.body)
      assert_match(/https:\/\/admin.github.com\/stafftools\/enterprises\/#{@business.slug}/, issue.body)
      assert_match(/Once we have an updated Subscription ID, visit/, issue.body)
      assert_match(/https:\/\/admin.github.com\/stafftools\/enterprises\/#{@business.slug}\/billing/, issue.body)
      assert_same_elements [enterprise_account_setup_label, sales_support_label], issue.labels
    end

    test "opens an issue on the sales-operations repo for an organization" do
      github_organization = create(:organization, :with_azure_subscription, login: "github")
      sales_operations_repository = create(:repository, owner: github_organization, name: "sales-operations")
      enterprise_account_setup_label = create(:label, repository: sales_operations_repository, name: "Enterprise Account Set-up")
      sales_support_label = create(:label, repository: sales_operations_repository, name: "sales-support")
      subscription_digest = Digest::SHA256.hexdigest(github_organization.customer.azure_subscription_id)[0..12]

      Billing::Azure::InvalidSubscriptionNotifier.new.notify(org: github_organization)

      assert_equal 1, sales_operations_repository.issues.count
      issue = sales_operations_repository.issues.first

      assert_equal "Azure Subscription ID is invalid for #{github_organization.name}, #{subscription_digest}", issue.title
      assert_match(/check for Azure Subsription ID status failed at/, issue.body)
      assert_match(/Organization/, issue.body)
      assert_match(/_Please have their sales rep reach out to get this rectified/, issue.body)
      assert_match(/Stafftools/, issue.body)
      assert_match(/Reach out to the account contact at/, issue.body)
      assert_match(/https:\/\/admin.github.com\/stafftools\/users\/#{github_organization.to_param}/, issue.body)
      assert_match(/Once we have an updated Subscription ID, visit/, issue.body)
      assert_match(/https:\/\/admin.github.com\/stafftools\/users\/#{github_organization.to_param}\/billing/, issue.body)
      refute_match(/Terms of Service Notes/, issue.body)
      assert_same_elements [enterprise_account_setup_label, sales_support_label], issue.labels
    end

    test "comments if an open issue with digest already exists" do
      GitHub.flipper[:pause_invalid_subscription_notifier].disable(@business)
      github_organization = create(:organization, login: "github")
      sales_operations_repository = create(:repository, owner: github_organization, name: "sales-operations")
      enterprise_account_setup_label = create(:label, repository: sales_operations_repository, name: "Enterprise Account Set-up")
      sales_support_label = create(:label, repository: sales_operations_repository, name: "sales-support")

      subscription_digest = Digest::SHA256.hexdigest(@business.customer.azure_subscription_id)[0..12]
      issue = sales_operations_repository.issues.create!(
        user: User.staff_user,
        title: "Azure Subscription ID is invalid for #{@business.name}, #{subscription_digest}"
      )

      Billing::Azure::InvalidSubscriptionNotifier.new.notify(business: @business)

      issue = sales_operations_repository.issues.last
      assert_equal 1, issue.comments.count
      comment = issue.comments.first
      assert_match(/Subscription ID for customer #{@business.name} is still invalid at/, comment.body)
    end

    test "does NOT comments if an open issue with digest already exists but 'pause_invalid_subscription_notifier' flag is enabled for business" do
      GitHub.flipper[:pause_invalid_subscription_notifier].enable(@business)
      github_organization = create(:organization, login: "github")
      sales_operations_repository = create(:repository, owner: github_organization, name: "sales-operations")
      enterprise_account_setup_label = create(:label, repository: sales_operations_repository, name: "Enterprise Account Set-up")
      sales_support_label = create(:label, repository: sales_operations_repository, name: "sales-support")

      subscription_digest = Digest::SHA256.hexdigest(@business.customer.azure_subscription_id)[0..12]
      issue = sales_operations_repository.issues.create!(
        user: User.staff_user,
        title: "Azure Subscription ID is invalid for #{@business.name}, #{subscription_digest}"
      )

      Billing::Azure::InvalidSubscriptionNotifier.new.notify(business: @business)

      issue = sales_operations_repository.issues.last
      assert_equal 0, issue.comments.count
      refute issue.comments.first
    end

    test "ignores closed issue with digest" do
      github_organization = create(:organization, login: "github")
      sales_operations_repository = create(:repository, owner: github_organization, name: "sales-operations")
      enterprise_account_setup_label = create(:label, repository: sales_operations_repository, name: "Enterprise Account Set-up")
      sales_support_label = create(:label, repository: sales_operations_repository, name: "sales-support")

      subscription_digest = Digest::SHA256.hexdigest(@business.customer.azure_subscription_id)[0..12]
      title = "Azure Subscription ID is invalid for #{@business.name}, #{subscription_digest}"
      closed_issue = sales_operations_repository.issues.create!(
        user: User.staff_user,
        title: title,
        state: "closed"
      )

      Billing::Azure::InvalidSubscriptionNotifier.new.notify(business: @business)

      issue = sales_operations_repository.issues.where(id: closed_issue.id).last
      assert_equal 0, issue.comments.count, "closed issue should not have any comments."

      new_issue = sales_operations_repository.issues.where(title: title, state: "open").last
      refute_nil new_issue, "should open new issue with digest."
    end

    test "does nothing when sales-operations repository doesn't exist" do
      assert_no_difference -> { Issue.count } do
        Billing::Azure::InvalidSubscriptionNotifier.new.notify(business: @business)
      end
    end

    test "increments counter when sales-operations repository doesn't exist" do
      assert_no_difference -> { Issue.count } do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        Billing::Azure::InvalidSubscriptionNotifier.new.notify(business: @business)
        assert_equal 1, GitHub.dogstats.increments("billing.enterprise_agreement.sales_operations.repo_not_found").length
      end
    end
  end
end if GitHub.billing_enabled?
