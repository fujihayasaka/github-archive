# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthApplicationTransferTest < GitHub::TestCase
  fixtures do
    @stranger = create :user, login: "stranger"
    @admin    = create :user, login: "org-admin"
    @member   = create :user, login: "org-member"
    @org      = create :organization, login: "target-org"

    @org.add_admin @admin
    team = @org.teams.create(name: "Employees")
    team.add_member @member

    @app = create :oauth_application, \
      user: @admin,
      name: "Code Scanner Pro"

    @user_app = create :oauth_application, \
                user: @admin,
                name: "Adobe Photoshop"

    @org_app = create :oauth_application, \
      user: @org,
      name: "Microsoft Word"
  end

  context "user to org" do
    test "stores requester, application, and target" do
      xfer = OauthApplicationTransfer.new \
        requester: @admin,
        application: @app,
        target: @org

      xfer.save!
      xfer.reload

      assert_equal @admin, xfer.requester
      assert_equal @app, xfer.application
      assert_equal @org, xfer.target
    end

    test "requester must admin the application" do
      xfer = OauthApplicationTransfer.new \
        requester: @stranger,
        application: @app,
        target: @org

      refute xfer.valid?
      refute_empty xfer.errors[:requester]
    end

    test "responder must admin the target" do
      xfer = OauthApplicationTransfer.start \
        application: @app,
        target: @org,
        requester: @admin

      xfer.responder = @stranger

      refute xfer.valid?
      refute_empty xfer.errors[:responder]
    end

    test "sends email to target admins when requester is not an admin" do
      app = create :oauth_application, \
              user: @member,
              name: "Code Scanner 2000"

      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        xfer = OauthApplicationTransfer.start \
          application: app,
          target: @org,
          requester: @member
        refute_nil xfer
      end

      mail = ActionMailer::Base.deliveries.pop
      refute_nil mail

      assert_match "transfer", mail.subject
      assert_match "Code Scanner 2000", mail.body.to_s
    end

    test "does not send email when requester is admin of target" do
      ActionMailer::Base.deliveries.clear
      xfer = OauthApplicationTransfer.start \
        application: @app,
        target: @org,
        requester: @admin
      refute_nil xfer

      mail = ActionMailer::Base.deliveries.pop
      assert_nil mail
    end

    test "doesn't allow multiple transfers for the same application" do
      xfer = OauthApplicationTransfer.create! \
        requester: @admin,
        application: @app,
        target: @org

      requested = OauthApplicationTransfer.new \
        requester: @admin,
        application: @app,
        target: @org

      refute requested.valid?
    end
  end

  context "user to user" do
    test "stores requester, application, and target" do
      xfer = OauthApplicationTransfer.new \
        requester: @admin,
        application: @user_app,
        target: @member

      xfer.save!
      xfer.reload

      assert_equal @admin, xfer.requester
      assert_equal @user_app, xfer.application
      assert_equal @member, xfer.target
    end

    test "requester must own the application" do
      xfer = OauthApplicationTransfer.new \
        requester: @stranger,
        application: @user_app,
        target: @member

      refute xfer.valid?
      refute_empty xfer.errors[:requester]
    end

    test "sends email to target" do
      app = create :oauth_application, \
              user: @admin,
              name: "Code Scanner 2000"

      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        xfer = OauthApplicationTransfer.start \
          application: app,
          target: @member,
          requester: @admin
        refute_nil xfer
      end
      mail = ActionMailer::Base.deliveries.pop
      refute_nil mail

      assert_match "transfer", mail.subject
      assert_match "Code Scanner 2000", mail.body.to_s
    end

    test "doesn't allow multiple transfers for the same application" do
      xfer = OauthApplicationTransfer.create! \
        requester: @admin,
        application: @user_app,
        target: @member

      requested = OauthApplicationTransfer.new \
        requester: @admin,
        application: @user_app,
        target: @member

      refute requested.valid?
    end

    test "doesn't allow transfer if target blocks requester" do
      requester = create(:user)
      target = create(:user)
      target.block(requester, actor: target)

      app = create :oauth_application, \
              user: requester,
              name: "Meme Generator 9000"

      xfer = OauthApplicationTransfer.new \
        application: app,
        target: target,
        requester: requester

      refute xfer.valid?
    end

    test "doesn't allow transfer if requester is spammy" do
      requester = create :user, spammy: true
      target = create(:user)

      app = create :oauth_application, \
              user: requester,
              name: "Meme Generator 9000"

      xfer = OauthApplicationTransfer.new \
        application: app,
        target: target,
        requester: requester

      refute xfer.valid?
    end if GitHub.spamminess_check_enabled?
  end

  context "org to user" do
    test "stores requester, application, and target" do
      xfer = OauthApplicationTransfer.new \
        requester: @org,
        application: @org_app,
        target: @member

      xfer.save!
      xfer.reload

      assert_equal @org, xfer.requester
      assert_equal @org_app, xfer.application
      assert_equal @member, xfer.target
    end

    test "requester must admin the application" do
      xfer = OauthApplicationTransfer.new \
        requester: @stranger,
        application: @org_app,
        target: @member

      refute xfer.valid?
      refute_empty xfer.errors[:requester]
    end

    test "sends email to target" do
      app = create :oauth_application, \
              user: @org,
              name: "Code Scanner 2000"

      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        xfer = OauthApplicationTransfer.start \
          application: app,
          target: @member,
          requester: @admin
        refute_nil xfer
      end
      mail = ActionMailer::Base.deliveries.pop
      refute_nil mail

      assert_match "transfer", mail.subject
      assert_match "Code Scanner 2000", mail.body.to_s
    end

    test "doesn't allow multiple transfers for the same application" do
      xfer = OauthApplicationTransfer.create! \
        requester: @org,
        application: @org_app,
        target: @admin

      requested = OauthApplicationTransfer.new \
        requester: @org,
        application: @org_app,
        target: @admin

      refute requested.valid?
    end
  end

  test "instruments transfer" do
    other_admin = create :user, login: "other-admin"
    @org.add_admin(other_admin)
    xfer = OauthApplicationTransfer.create! \
      requester: @admin,
      application: @app,
      target: @org

    events = subscribe "oauth_application.transfer"

    xfer.finish other_admin

    expected_payload = {
      requester: @admin.login,
      requester_id: @admin.id,
      responder: other_admin.login,
      responder_id: other_admin.id,
      oauth_application: @app.name,
      oauth_application_id: @app.id,
      application_url: @app.url,
      callback_url: @app.callback_url,
      user: @admin.login,
      user_id: @admin.id,
      state: 0,
      rate_limit: 5000,
      transfer_from: @admin.login,
      transfer_from_id: @admin.id,
      transfer_to: @org.login,
      transfer_to_id: @org.id,
    }

    assert event = events.pop, "not instrumented"
    assert_equal "oauth_application.transfer", event.name
    assert_equal expected_payload, event.payload
  end
end
