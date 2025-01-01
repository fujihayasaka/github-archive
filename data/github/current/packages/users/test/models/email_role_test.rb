# typed: false
# frozen_string_literal: true

require "test_helper"

class EmailRoleTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @email = @user.emails.first
    @email.verify!
    @primary_role = @email.email_roles.primary.first
    @backup_email = create(:user_email, user: @user)
    @backup_email.verify!
    @user.set_backup_email(@backup_email)
    @backup_role = @backup_email.email_roles.backup.first
  end

  test "requires role" do
    @primary_role.role = nil
    assert @primary_role.invalid?
    assert_includes @primary_role.errors[:role], "can't be blank"
  end

  test "requires unique role per email" do
    new_email_role = build(:email_role, role: @primary_role.role, email: @primary_role.email)
    refute_predicate new_email_role, :valid?
    assert_includes new_email_role.errors[:role], "has already been taken"
  end

  test "fails at the database level when there are multiple of the same email role for an email" do
    new_email_role = build(:email_role, role: @primary_role.role, email: @primary_role.email)

    assert_raises ActiveRecord::RecordNotUnique do
      new_email_role.save!(validate: false)
    end
  end

  test "has query methods for all the roles" do
    EmailRole::Roles.each do |role|
      method = "#{role}?"
      role = EmailRole.new(role: role)
      assert role.send(method)
    end
  end

  test "has primary role" do
    assert_equal "primary", @primary_role.role
  end

  test "has backup role" do
    assert_equal "backup", @backup_role.role
  end

  test "has a primary scope" do
    primary_email_role = @user.email_roles.primary.first
    assert primary_email_role
    assert_equal @user, primary_email_role.user
  end

  test "has a backup scope" do
    backup_email_role = @user.email_roles.backup.first
    assert backup_email_role
    assert_equal @user, backup_email_role.user
  end

  test "has email roles" do
    assert_equal 1, @user.email_roles.primary.size
    primary_email = @user.email_roles.primary.first
    assert_equal @email, primary_email.email
    assert_equal @user, primary_email.user
  end

  test "is accessible from both sides of the relationship" do
    assert_equal @user.email_roles.primary.first, @email.email_roles.primary.first
  end

  test "cannot delete primary email if there is only one email" do
    @user.emails = []
    @user.add_email("new-email@example.com", is_primary: true).verify!

    assert_raises(EmailRole::CannotDeleteLastPrimaryEmail) do
      @user.emails.first.destroy
    end
  end

  test "can delete primary email when another verified email exists" do
    @user.emails = []
    @user.add_email("new-email@example.com", is_primary: true).verify!
    @user.add_email("second@example.com").verify!

    assert @user.primary_user_email.destroy
  end

  test "can delete primary email when another unverified email is present" do
    email2 = @user.add_email "second@example.com"
    assert email2.unverified?

    assert @user.primary_user_email.destroy
  end

  test "cannot delete last primary email when there are stealth emails" do
    @user.emails = []
    @user.add_email("new-email@example.com", is_primary: true).verify!
    assert_equal 1, @user.emails.count
    # Toggling visibility auto-creatse a new `no-reply` email.
    @user.emails.first.toggle_visibility
    assert_equal 2, @user.emails.count
    assert_equal 1, @user.emails.notifiable.count
    assert_raises(EmailRole::CannotDeleteLastPrimaryEmail) do
      @user.emails.first.destroy
    end
  end

  test "cannot remove primary email when only other email is backup email" do
    @user.emails = []
    primary_email = @user.add_email("new-email@example.com", is_primary: true)
    primary_email.verify!
    backup_email = @user.add_email("new-backup-email@example.com")
    backup_email.verify!
    @user.set_backup_email(backup_email)
    assert_equal 2, @user.emails.count
    refute @user.remove_email(primary_email)
    assert primary_email.reload
    assert primary_email, @user.reload.primary_user_email
  end

  test "removing an email also removes all of the non-primary email roles" do
    new_email = @user.add_email "new-email@example.com"
    new_email.mark_as_suppressed!
    email_role = new_email.email_roles.suppressed.first
    assert_equal "suppressed", email_role.role

    @user.remove_email "new-email@example.com"
    assert_nil EmailRole.find_by_id(email_role.id)
  end

  test "removing an email reassigns the primary email role" do
    new_email = @user.add_email "new-email@example.com", is_primary: true
    assert_equal new_email, @user.primary_user_email
    email_role = @user.primary_user_email.primary_role
    assert_equal "primary", email_role.role

    @user.remove_email "new-email@example.com"
    refute_equal new_email, @user.primary_user_email
    assert_equal email_role, @user.primary_user_email.primary_role
  end

  test "removing a hard bounce triggers a sendgrid suppression removal" do
    new_hard_bounce = @user.add_email "triggers@example.com"
    new_hard_bounce.mark_as_bouncing!

    if GitHub.sendgrid_enabled?
      assert_enqueued_with(job: SendgridSuppressionRemovalJob, args: [new_hard_bounce.id]) do
        new_hard_bounce.destroy
      end
    else
      assert_no_enqueued_jobs do
        new_hard_bounce.destroy
      end
    end
  end
end

class EmailRoleInstrumentationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "instruments email role create" do
    events = subscribe "email_role.create"
    email = @user.add_email "test@example.com"
    email.mark_as_bouncing!

    expected_payload = {
      email_role: "hard_bounce",
      email_role_id: email.bouncing.id,
      email: "test@example.com",
      email_id: email.id,
      user: email.user.login,
      user_id: email.user.id,
    }
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end
end

class EmailRoleAuditingTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @user = create(:user)
  end

  test "audits email role creation" do
    events = subscribe "email_role.create"
    email = nil
    with_es_refresh do
      email = @user.emails.first
      assert role = email.mark_as_bouncing!
    end

    expected_payload = {
      email_role: "hard_bounce",
      email_role_id: email.bouncing.id,
      email: email.email,
      email_id: email.id,
      user: email.user.login,
      user_id: email.user.id,
    }
    assert event = events.pop
    assert_equal expected_payload, event.payload
  end
end

class EmailRoleWhenThereAreMultipleUserEmailsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @email1 = @user.emails.first
    assert @email1.primary_role?
    @email1.verify!
    @email2 = create :user_email, :verified, email: "second@example.com", user: @user
  end

  test "secondary emails have no default role" do
    assert_equal [], @email2.email_roles
  end

  test "can only have one email assigned as primary" do
    role = @email2.email_roles.build(user: @user, role: "primary")
    refute role.valid?
    assert_equal ["Cannot assign multiple primary emails"], role.errors[:base]
  end

  test "can only have one email assigned as backup" do
    # First set an initial backup email
    @user.set_backup_email(@email2)
    @user.reload_backup_user_email_role

    # The second role to receive the backup role should fail.
    backup_email = create :user_email, :verified, email: "bakup@example.com", user: @user
    role = backup_email.email_roles.build(user: @user, role: "backup")
    refute_predicate role, :valid?
    assert_equal ["Cannot assign multiple backup emails"], role.errors[:base]
  end

  test "can only have one EmailRole of any one type per UserEmail" do
    @email1.email_roles.create!(user: @user, role: "hard_bounce")
    role = @email1.email_roles.build(user: @user, role: "hard_bounce")
    refute role.valid?, "should be invalid due to multiple hard_bounce roles"
    assert_equal "has already been taken", role.errors[:role].first
  end

  test "deleting primary email sets the other email as primary" do
    @user.remove_email @email1
    @user.reload
    assert_equal 1, @user.emails.count
    assert_equal 1, @user.email_roles.primary.count
    assert_equal @email2, @user.reload.email_roles.primary.first.email
  end

  test "can toggle visibility for primary role" do
    assert @email1.primary_role.public?
    @email1.primary_role.toggle_visibility
    assert @email1.primary_role.private?
    @email1.primary_role.toggle_visibility
    assert @email1.primary_role.public?
  end
end
