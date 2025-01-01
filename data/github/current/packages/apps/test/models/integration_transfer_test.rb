# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class IntegrationTransferTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @stranger = create :user, login: "stranger"
    @admin    = create :user, login: "org-admin"
    @member   = create :user, login: "org-member"
    @org      = create :organization, login: "target-org"

    @org.add_admin @admin
    team = @org.teams.create(name: "Employees")
    team.add_member @member

    @integration      = create(:integration, owner: @admin, name: "Code Scanner Pro")
    @user_integration = create(:integration, owner: @admin, name: "Adobe Photoshop")
    @org_integration  = create(:integration, owner: @org, name: "Microsoft Word")
  end

  context "validation" do
    test "requires a valid integration" do
      @integration.update_attribute(:name, "GitHub Gist"); @integration.reload
      refute_predicate @integration, :valid?

      xfer = assert_raises ActiveRecord::RecordInvalid do
        IntegrationTransfer.start(
          integration: @integration,
          target: @org,
          requester: @admin,
        )
      end

      assert_equal "Validation failed: Name should not begin with 'GitHub' or 'Gist', Name should not generate slugs that begin with 'GitHub' or 'Gist'", xfer.message
    end
  end

  context "user to org" do
    test "stores requester, integration, and target" do
      xfer = IntegrationTransfer.new(
        requester: @admin,
        integration: @integration,
        target: @org,
      )

      xfer.save!
      xfer.reload

      assert_equal @admin, xfer.requester
      assert_equal @integration, xfer.integration
      assert_equal @org, xfer.target
    end

    test "responder must admin the target" do
      xfer = IntegrationTransfer.start(
        integration: @integration,
        target: @org,
        requester: @admin,
      )

      xfer.responder = @stranger

      refute xfer.valid?
      refute_empty xfer.errors[:responder]
    end

    test "sends email to target admins when requester is not an admin" do
      integration = create(:integration,
        owner: @member,
        name: "Code Scanner 2000",
      )

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        ActionMailer::Base.deliveries.clear
        xfer = IntegrationTransfer.start(
          integration: integration,
          target: @org,
          requester: @member,
        )
        refute_nil xfer
      end

      mail = ActionMailer::Base.deliveries.pop
      refute_nil mail

      assert_match "transfer", mail.subject
      assert_match "Code Scanner 2000", mail.body.to_s
    end

    test "does not send email when requester is admin of target" do
      ActionMailer::Base.deliveries.clear
      xfer = IntegrationTransfer.start(
        integration: @integration,
        target: @org,
        requester: @admin,
      )
      refute_nil xfer
      mail = ActionMailer::Base.deliveries.pop
      assert_nil mail
    end

    test "doesn't allow multiple transfers for the same integration" do
      IntegrationTransfer.create!(
        requester: @admin,
        integration: @integration,
        target: @org,
      )

      requested = IntegrationTransfer.new(
        requester: @admin,
        integration: @integration,
        target: @org,
      )

      refute requested.valid?
    end
  end

  context "user to user" do
    test "stores requester, integration, and target" do
      xfer = IntegrationTransfer.new(
        requester: @admin,
        integration: @user_integration,
        target: @member,
      )

      xfer.save!
      xfer.reload

      assert_equal @admin, xfer.requester
      assert_equal @user_integration, xfer.integration
      assert_equal @member, xfer.target
    end

    test "sends email to target" do
      integration = create(:integration,
        owner: @admin,
        name: "Code Scanner 2000",
      )

      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        xfer = IntegrationTransfer.start(
          integration: integration,
          target: @member,
          requester: @admin,
        )
        refute_nil xfer
      end
      mail = ActionMailer::Base.deliveries.pop
      refute_nil mail

      assert_match "transfer", mail.subject
      assert_match "Code Scanner 2000", mail.body.to_s
    end

    test "doesn't allow multiple transfers for the same integration" do
      IntegrationTransfer.create!(
        requester: @admin,
        integration: @user_integration,
        target: @member,
      )

      requested = IntegrationTransfer.new(
        requester: @admin,
        integration: @user_integration,
        target: @member,
      )

      refute requested.valid?
    end

    test "doesn't allow transfer if target blocks requester" do
      requester = create(:user)
      target    = create(:user)

      target.block(requester, actor: target)

      integration = create(:integration,
        owner: requester,
        name: "Meme Generator 9000",
      )

      xfer = IntegrationTransfer.new(
        integration: integration,
        target: target,
        requester: requester,
      )

      refute xfer.valid?
    end

    test "doesn't allow transfer if requester is spammy" do
      requester = create :user, spammy: true
      target = create(:user)

      integration = create(:integration,
        owner: requester,
        name: "Meme Generator 9000",
      )

      xfer = IntegrationTransfer.new(
        integration: integration,
        target: target,
        requester: requester,
      )

      refute xfer.valid?
    end if GitHub.spamminess_check_enabled?
  end

  context "org to user" do
    test "stores requester, integration, and target" do
      xfer = IntegrationTransfer.new \
        requester: @org,
        integration: @org_integration,
        target: @member

      xfer.save!
      xfer.reload

      assert_equal @org, xfer.requester
      assert_equal @org_integration, xfer.integration
      assert_equal @member, xfer.target
    end

    test "sends email to target" do
      integration = create :integration, \
        owner: @org,
        name: "Code Scanner 2000"

      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        xfer = IntegrationTransfer.start(
          integration: integration,
          target: @member,
          requester: @admin,
        )
        refute_nil xfer
      end

      mail = ActionMailer::Base.deliveries.pop
      refute_nil mail

      assert_match "transfer", mail.subject
      assert_match "Code Scanner 2000", mail.body.to_s
    end

    test "doesn't allow multiple transfers for the same integration" do
      IntegrationTransfer.create!(
        requester: @org,
        integration: @org_integration,
        target: @admin,
      )

      requested = IntegrationTransfer.new(
        requester: @org,
        integration: @org_integration,
        target: @admin,
      )

      refute requested.valid?
    end

    context "#cancellable_by?" do
      test "is cancellable by any org admin" do
        other_admin = create(:user, login: "other-admin")
        @org.add_admin(other_admin)

        xfer = IntegrationTransfer.new(requester: other_admin, integration: @org_integration, target: @member)
        assert xfer.cancelable_by?(@admin), "expected #{@admin} to be able to cancel the transfer"
      end

      test "is cancellable by a app manager that manages all apps" do
        all_apps_manager = create(:user, login: "all-apps-manager-#{SecureRandom.hex(6)}")
        @org.add_member(all_apps_manager)

        grant_manage_all_apps_permission(member: all_apps_manager, org: @org)
        xfer = IntegrationTransfer.new(requester: @admin, integration: @org_integration, target: @member)

        assert xfer.cancelable_by?(all_apps_manager), "expected #{all_apps_manager} to be able to cancel the transfer"
      end

      test "is cancellable by an app manager that can manage the single app" do
        app_manager = create(:user, login: "app-manager-#{SecureRandom.hex(6)}")
        @org.add_member(app_manager)

        grant_manage_app_permission(member: app_manager, app: @org_integration)
        xfer = IntegrationTransfer.new(requester: @admin, integration: @org_integration, target: @member)

        assert xfer.cancelable_by?(app_manager), "expected #{app_manager} to be able to cancel the transfer"
      end

      test "is not cancellable by an app manager that cannot manage the app in question" do
        app_manager = create(:user, login: "app-manager-#{SecureRandom.hex(6)}")
        @org.add_member(app_manager)

        integration = create(:integration, owner: @org)

        grant_manage_app_permission(member: app_manager, app: @org_integration)
        xfer = IntegrationTransfer.new(requester: @admin, integration: integration, target: @member)

        refute xfer.cancelable_by?(app_manager), "expected #{app_manager} to not be able to cancel the transfer"
      end
    end
  end

  test "instruments transfer" do
    other_admin = create :user, login: "other-admin"
    @org.add_admin(other_admin)
    xfer = IntegrationTransfer.create!(
      requester: @admin,
      integration: @integration,
      target: @org,
    )

    events = subscribe "integration.transfer"

    xfer.finish(other_admin, entry_point: :test_case)

    expected_payload = {
      integration: @integration.name,
      app: @integration.name,
      name: @integration.name,
      slug: @integration.slug,
      integration_id: @integration.id,
      app_id: @integration.id,
      user: @admin.login,
      user_id: @admin.id,
      requester: @admin.login,
      requester_id: @admin.id,
      responder: other_admin.login,
      responder_id: other_admin.id,
      transfer_from: @admin.login,
      transfer_from_id: @admin.id,
      transfer_to: @org.login,
      transfer_to_id: @org.id,
    }

    assert event = events.pop, "not instrumented"
    assert_equal "integration.transfer", event.name
    assert_equal expected_payload, event.payload
  end
end
