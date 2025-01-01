# typed: true
# frozen_string_literal: true

require "test_helper"

class DestroyUserCallbacksTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
  end

  test "Destroying a user calls #before_destroy and #after_commit" do
    DestroyUserCallbacks.any_instance.expects(:before_destroy).with(@user).once
    DestroyUserCallbacks.any_instance.expects(:after_commit).with(@user).once
    @user.destroy
  end

  test "#before_destroy tracks a destroy attempted" do
    DestroyUserCallbacks.any_instance.expects(:after_commit).with(@user).once
    @user.destroy
    assert_dogstats_increment(1, "user", tags: ["action:destroy_attempted"])
  end

  test "if an exception is thrown in #before_destroy the exception is logged and reraised" do
    error = ActiveRecord::RecordNotFound.new("No one left to follow")
    DestroyUserCallbacks.any_instance.expects(:remove_followers).with(@user).raises(error)
    GitHub.logger.expects(:error).with(has_entries(
      exception: error,
      "code.namespace": "DestroyUserCallbacks",
      "code.function": "before_destroy",
      "gh.user.id": @user.id,
    ))
    assert_raises(ActiveRecord::RecordNotFound) do
      @user.destroy
      assert_dogstats_increment(1, "user", tags: ["action:destroy_failed"])
    end
  end

  test "it destroys the destroyed user's protected domains", skip_enterprise: true do
    assert_enqueued_jobs 1, queue: :pages_domain_protection do
      @user.destroy

      assert_enqueued_with(job: Pages::DeleteProtectedDomainsJob, args: [
        owner_id: @user.id,
      ])
    end
  end

  test "does not destroy the destroyed user's protected domains on GHES", enterprise_only: true do
    assert_no_enqueued_jobs(queue: :pages_domain_protection) do
      @user.destroy
    end
  end

  context "deletion locking" do
    test "locks installation target for deletion" do
      installation = make_integration_installation(target: @user)
      @user.destroy

      assert IntegrationInstallation.target_locked_for_deletion?(installation)
    end

    test "uninstalls integration" do
      installation = make_integration_installation(target: @user)
      @user.destroy

      assert IntegrationInstallation.target_locked_for_deletion?(installation)
      assert_nil IntegrationInstallation.find_by(id: installation.id)
    end
  end

  test "destroy sends confirmation email" do
    org = create(:organization)
    AccountMailer.expects(:delete_org).once.returns(stub(deliver_later: nil))
    org.destroy
  end unless GitHub.enterprise?

  test "destroy does not send confirmation email if gh_role=staff_delete" do
    org = create(:organization, gh_role: "staff_delete")
    AccountMailer.expects(:delete_org).never
    org.destroy
  end unless GitHub.enterprise?

  test "destroy nevers sends confirmation email in enterprise" do
    org = create(:organization)
    AccountMailer.expects(:delete_org).never
    org.destroy
  end if GitHub.enterprise?
end
