# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class PendingAutomaticInstallationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, :minimal, owner: @user)

    @subject = PendingAutomaticInstallation.create!(
      trigger_type: PendingAutomaticInstallation::ALLOWED_TRIGGER_TYPES.first,
      target: @user,
    )
  end

  context "validations" do
    test "requires a valid target" do
      @subject.target = nil

      refute_predicate @subject, :valid?
      refute_empty @subject.errors[:target_type]

      @subject.target = Integration.new
      refute_predicate @subject, :valid?
      refute_empty @subject.errors[:target_type]

      @subject.target = @user
      @subject.save

      assert_predicate @subject, :persisted?, @subject.errors
    end

    test "requires a valid trigger" do
      @subject.trigger_type = "foo"

      refute_predicate @subject, :valid?
      refute_empty @subject.errors[:trigger_type]

      @subject.trigger_type = PendingAutomaticInstallation::ALLOWED_TRIGGER_TYPES.first
      @subject.save

      assert_predicate @subject, :persisted?, @subject.errors
    end
  end

  context "callbacks" do
    test "records installed_at after the app is installed" do
      assert_nil @subject.installed_at
      @subject.installed!
      refute_nil @subject.installed_at
    end
  end

  test "is #pending? by default" do
    assert_predicate PendingAutomaticInstallation.new, :pending?
  end

  context "#targeted_user" do
    test "returns the user when :target is a user" do
      assert_equal @user, @subject.targeted_user
    end

    test "returns the repository owner when the taget is a repo" do
      pending_installation = make_pending_automatic_installation(target: @repo)
      assert_equal @user, @subject.targeted_user
    end
  end

  context "#targeted_repository_ids" do
    test "returns an empty array when :target is a user" do
      assert_equal [], @subject.targeted_repository_ids
    end

    test "returns a single repo id array when the :target is a repo" do
      pending_installation = make_pending_automatic_installation(target: @repo)
      assert_equal [@repo.id], pending_installation.targeted_repository_ids
    end
  end

  context "#stale?" do
    test "it's stale when a targeted user is deleted" do
      refute_predicate @subject, :stale?
      @user.destroy
      assert_predicate @subject.reload, :stale?
    end

    test "it's stale when a targeted repo is deleted" do
      pending_installation = make_pending_automatic_installation(target: @repo)
      refute_predicate pending_installation, :stale?
      @repo.destroy
      assert_predicate pending_installation.reload, :stale?
    end

    test "it's stale when a the owner of a targeted repo is deleted" do
      pending_installation = make_pending_automatic_installation(target: @repo)
      refute_predicate pending_installation, :stale?
      @repo.owner.destroy
      assert_predicate pending_installation.reload, :stale?
    end
  end

  test "it has a valid factory helper" do
    other_user = create(:user)
    assert_predicate make_pending_automatic_installation(target: other_user), :valid?
  end
end
