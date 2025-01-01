# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableCustomEmailRoutingTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @email = "emailaddress@github.com"
    @restorable = Restorable.create
  end

  test ".restore adds custom email routing for org" do
    @user.add_email(@email).verify!
    @restorable.custom_email_routings.create(
      organization_id: @org.id,
      email: @email,
    )

    settings = stub("user_notification_settings")
    settings.expects(:default_email_address).returns(@user.email)
    settings.expects(:set_notification_email).once.with("org-#{@org.id}", @email)
    settings.expects(:clear_unverified_emails).with(@user.notifiable_emails).returns(nil)
    Restorable::CustomEmailRouting.expects(:build_user_notification_settings).returns(settings)

    Restorable::CustomEmailRouting.restore(
      restorable: @restorable,
      user: @user,
    )
  end

  test ".restore doesn't add custom email routing for org if email is primary email" do
    @user.add_email(@email).verify!
    @restorable.custom_email_routings.create(
      organization_id: @org.id,
      email: @email,
    )

    settings = stub("user_notification_settings")
    settings.expects(:default_email_address).returns(@email)
    settings.expects(:set_notification_email).never
    settings.expects(:clear_unverified_emails).with(@user.notifiable_emails).returns(nil)
    Restorable::CustomEmailRouting.expects(:build_user_notification_settings).returns(settings)

    Restorable::CustomEmailRouting.restore(
      restorable: @restorable,
      user: @user,
    )
  end

  test ".restore adds multiple custom email routing for org" do
    org2 = create(:organization)
    email2 = "secondemailaddress@github.com"
    @user.add_email(@email).verify!
    @user.add_email(email2).verify!

    @restorable.custom_email_routings.create(
      organization_id: @org.id,
      email: @email,
    )
    @restorable.custom_email_routings.create(
      organization_id: org2.id,
      email: email2,
    )

    settings = stub("user_notification_settings")
    settings.expects(:default_email_address).twice.returns(@user.email)
    settings.expects(:set_notification_email).once.with("org-#{@org.id}", @email)
    settings.expects(:set_notification_email).once.with("org-#{org2.id}", email2)
    settings.expects(:clear_unverified_emails).with(@user.notifiable_emails).returns(nil)
    Restorable::CustomEmailRouting.expects(:build_user_notification_settings).returns(settings)

    Restorable::CustomEmailRouting.restore(
      restorable: @restorable,
      user: @user,
    )
  end

  test ".backup saves custom email routing" do
    assert_difference "Restorable::CustomEmailRouting.count", 1 do
      Restorable::CustomEmailRouting.backup(
        restorable: @restorable,
        org_id_and_email_hash: { @org.id => @email },
      )
    end
    restorable = Restorable::CustomEmailRouting.first
    assert_equal @email, T.must(restorable).email
    assert_equal @org.id, T.must(restorable).organization_id
  end
end
