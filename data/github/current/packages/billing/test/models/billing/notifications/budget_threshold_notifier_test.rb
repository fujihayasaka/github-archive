# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Notifications
  class BudgetThresholdNotifierTest < GitHub::TestCase
    include Billing::Platform::Api::Utils

    fixtures do
      @user = create(:credit_card_user, plan: "free")
      @business = create(:business)
      @organization = create(:organization, business: @business, admin: @user)
    end

    setup do
      @budget = create(:budget, targetId: @business.customer.id, targetType: CUSTOMER_TARGET, pricingTargetType: "ProductPricing", pricingTargetId: "git_lfs", currentAmount: 75.0, threshold_percentage: 75.0, threshold_alertable: true, recipientUserIds: [@user.id])
      @notification = ::Billing::Notifications::BudgetNotification.new(budget: @budget).serialize
    end

    context "#call" do
      test "sends email" do
        assert_difference -> { ActionMailer::Base.deliveries.count }, 1, "A notification email wasn't sent" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end
      end

      test "sends email with the correct text for the budget's scope and product" do
        assert_difference -> { ActionMailer::Base.deliveries.count }, 1, "A notification email wasn't sent" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end

        assert_includes @notification.text,  "Git LFS"
        assert_includes @notification.text,  "Enterprise"
      end

      test "does not send email if email has already been sent" do
        notifier = Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification)
        key = notifier.send(:build_email_identifier)
        Billing::Kv.store.set(key, "true")

        assert_no_difference -> { ActionMailer::Base.deliveries.count }, "A notification email should not have been sent" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob)  do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end
      end

      test "does not send duplicate email for the same threshold" do
        Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call

        assert_no_difference -> { ActionMailer::Base.deliveries.count }, "A notification email should not have been sent" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob)  do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end
      end

      test "sends email if the threshold changes up or down" do
        # first notify at 75%
        assert_difference -> { ActionMailer::Base.deliveries.count }, 1, "A notification email wasn't sent" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end

        # when threshold goes up to 90%, we should notify
        @budget[:budgetState][:currentAmount] = 90.0
        @budget[:budgetState][:thresholdMet][:minimumUsagePercentage] = 90.0
        @notification = T.must(Billing::Notifications::BudgetNotification.new(budget: @budget).serialize)

        assert_difference -> { ActionMailer::Base.deliveries.count }, 1, "A notification email wasn't sent" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end

        # if threshold changes to 75% without target amount changing, we should not notify again (this shouldn't happen anyways)
        @budget[:budgetState][:currentAmount] = 75.0
        @budget[:budgetState][:thresholdMet][:minimumUsagePercentage] = 75.0
        @notification = T.must(Billing::Notifications::BudgetNotification.new(budget: @budget).serialize)

        assert_no_difference -> { ActionMailer::Base.deliveries.count }, "A notification email wasn't sent incorrectly" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end

        # if threshold comes down to 75% due to change in target amount, we should notify again
        @budget[:budgetState][:currentAmount] = 150.0
        @budget[:budget][:targetAmount] = 200.0
        @budget[:budgetState][:thresholdMet][:minimumUsagePercentage] = 75.0
        @notification = T.must(Billing::Notifications::BudgetNotification.new(budget: @budget).serialize)

        assert_difference -> { ActionMailer::Base.deliveries.count }, 1, "A notification email wasn't sent" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end
      end

      test "sends email to email recipients as well" do
        new_email = create :billing_external_email, owner: @business, email: "external@github.com"

        assert_difference -> { ActionMailer::Base.deliveries.count }, 1, "Notification emails weren't sent" do
          perform_enqueued_jobs(only: ApplicationDeliveryJob) do
            Billing::Notifications::BudgetThresholdNotifier.new(notification: @notification).call
          end
        end
      end
    end
  end
end if GitHub.billing_enabled?
