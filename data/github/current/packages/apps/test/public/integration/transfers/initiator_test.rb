# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationTransfersInitiatorTest < GitHub::TestCase
  fixtures do
    @target = create(:organization)
    @target_admin = @target.admins.first
    @member = create(:user)
    @target.add_member(@member)
    @integration = create(:integration, owner: @target_admin)
  end

  context "#start!" do
    test "returns a unsuccessful result if invalid" do
      Integration::Transfers::Validator.any_instance.stubs(:valid?).returns(false)

      result = Integration::Transfers::Initiator.new(
        integration: @integration,
        target: @target,
        requester: @target_admin
      ).start!

      refute result.success?
      assert_equal "Invalid transfer", result.message
    end

    test "returns a successful result if valid" do
      result = Integration::Transfers::Initiator.new(
        integration: @integration,
        target: @target,
        requester: @target_admin
      ).start!

      assert result.success?
      assert_equal "Transfer started", result.message
    end

    test "sends email to target admins when requester is not an admin" do
      integration = create(:integration,
        owner: @member,
        name: "Code Scanner 2000",
      )

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        result = Integration::Transfers::Initiator.new(
          integration: integration,
          target: @target,
          requester: @member
        ).start!

        assert result.success?
        assert_equal "Transfer started", result.message
      end

      mail = ActionMailer::Base.deliveries.pop
      refute_nil mail

      assert_match "transfer", mail.subject
      assert_match "Code Scanner 2000", mail.body.to_s
    end

    test "does not send email when requester is admin of target" do
      ActionMailer::Base.deliveries.clear

      result = Integration::Transfers::Initiator.new(
        integration: @integration,
        target: @target,
        requester: @target_admin
      ).start!

      assert result.success?
      assert_equal "Transfer started", result.message

      mail = ActionMailer::Base.deliveries.pop
      assert_nil mail
    end

    test "creates transfer record when successful" do
      assert_changes -> { IntegrationTransfer.count }, 1 do
        result = Integration::Transfers::Initiator.new(
          integration: @integration,
          target: @target,
          requester: @target_admin
        ).start!

        assert result.success?
        assert_equal "Transfer started", result.message

        xfer = T.must(IntegrationTransfer.last)
        assert_equal @integration, xfer.integration
        assert_equal @target, xfer.target
        assert_equal @target_admin, xfer.requester
      end
    end
  end
end
