# typed: true
# frozen_string_literal: true

require "test_helper"

class RenamingAUserTest < GitHub::TestCase

  RetiredNamespaceMock = Struct.new(:retired_namespace_exists, :first_retired_namespace)
  fixtures do
    @user   = create(:user)
    @repo   = create(:repository, owner: @user)
    @repo2  = create(:repository, owner: @user)
    @staff = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
  end

  setup do
    res = RetiredNamespaceMock.new(retired_namespace_exists: false, first_retired_namespace: "")
    ::PackageRegistry::Twirp::MetadataClient.any_instance.stubs(:check_packages_retired_namespace).returns(res)
  end

  test "existing locks on the user's repositories are not modified during a rename" do
    @repo.lock_excluding_descendants!(Repository::LockDependency::BILLING)
    assert @repo.locked
    refute @repo2.locked

    @user.rename!("foo")

    assert @repo.reload.locked
    refute @repo2.reload.locked
  end

  test "instruments user.rename event" do
    events = subscribe "user.rename"

    expected_payload = {
      user: "foo",
      user_id: @user.id,
      old_login: @user.login,
      rename_reason: nil,
      rename_notes: nil,
    }

    @user.rename!("foo")

    assert event = events.pop, "expected an event"
    assert_equal expected_payload, event.payload
  end

  test "users with reserved logins can be renamed", skip_with_all_emus: true do
    user = create :user
    user.update_attribute :login, "enterprise"
    assert_predicate user, :login_reserved?

    only = [AddToSearchIndexJob, CheckForSpamJob, UserRenameJob]
    perform_enqueued_jobs(only: only) do
      assert user.rename("enterprise-zz")
    end
    assert_equal "enterprise-zz", user.reload.login
    refute_predicate user, :login_reserved?
  end

  test "user that is a system account can't be renamed" do
    user = create(:user)
    user.stubs system_account?: true
    refute user.rename("renamed-user")
    message = "System accounts cannot be renamed."
    assert_equal message, user.errors[:base].first

  end

  test "organization that is a system account can't be renamed" do
    org = create(:organization)
    org.stubs system_account?: true
    refute org.rename("renamed-org")
    message = "System accounts cannot be renamed."
    assert_equal message, org.errors[:base].first
  end

  test "updates the repositories in the search index" do
    now = Time.now
    guid1 = AddToSearchIndexJob.guid("repository", @repo.id)
    guid2 = AddToSearchIndexJob.guid("repository", @repo2.id)

    timestamp = Timestamp.from_time(now)

    Timecop.freeze(now) do
      assert_enqueued_with job: AddToSearchIndexJob, args: ["repository", @repo.id,  { "submitted_at" => timestamp, "guid" => guid1 }] do
        assert_enqueued_with job: AddToSearchIndexJob, args: ["repository", @repo2.id, { "submitted_at" => timestamp, "guid" => guid2 }] do
          @user.rename!("foo")
        end
      end
    end

  end

  test "publishes a pages site directly after user rename if app is already installed" do
    pages_user = create(:user, login: "RudyTheDeveloper") # Need a name that's not all downcased.
    pages_repo = create(:repository, owner: pages_user, from_example: :pages)
    page       = pages_repo.create_page
    Repository.any_instance.expects(:should_install_pages_integration?).returns(false)
    Page.any_instance.expects(:publish).once
    AutomaticAppInstallation.expects(:trigger).never
    pages_user.rename!("foo")
  end

  test "queues automatic app install on pages site after user rename if app is not installed" do
    pages_user = create(:user, login: "RudyTheDeveloper") # Need a name that's not all downcased.
    pages_repo = create(:repository, owner: pages_user, from_example: :pages)
    page       = pages_repo.create_page
    Repository.any_instance.expects(:should_install_pages_integration?).returns(true)
    AutomaticAppInstallation.expects(:trigger).once
    pages_user.rename!("foo")
  end
end
