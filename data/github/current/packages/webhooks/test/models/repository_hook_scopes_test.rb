# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryHookScopesTest < GitHub::TestCase
  fixtures do
    @repo = create(:deleted_repository)
    @email_hook = create(:hook, name: "email", active: true, events: ["push"], installation_target: @repo, config: { address: "foo@example.com " })
    @web_hook   = create(:hook, name: "web",   active: true, events: ["push"], installation_target: @repo)
  end

  setup do
    enable_cache_storage
    reset_cache
  end

  context ".all_hooks scope" do
    test ".all_hooks includes email hooks" do
      assert_same_elements @repo.repo_hook_associations_ff? ? Hook.all_hooks_for_target(@repo) : @repo.all_hooks, [@email_hook, @web_hook]
    end

    test "destroying a repository should cleanup all hooks, including email" do
      assert Hook.find_by(id: @email_hook.id)
      assert Hook.find_by(id: @web_hook.id)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @repo.purge(synchronous: true) }

      refute Hook.find_by(id: @email_hook.id)
      refute Hook.find_by(id: @web_hook.id)
    end
  end

  context ".hooks scope" do
    test ".hooks does not include email service hooks" do
      refute_includes @repo.repo_hook_associations_ff? ? Hook.hooks_for_target(@repo) : @repo.hooks, @email_hook
    end
  end

  context ".email_hooks scope" do
    test ".email_hooks only includes email service, whether flag disabled or enabled" do
      assert_equal @repo.repo_hook_associations_ff? ? Hook.email_hooks_for_target(@repo) : @repo.email_hooks, [@email_hook]
    end

    test "creating a new email_hook will have the name attribute set" do
      @email_hook.destroy
      assert_empty @repo.repo_hook_associations_ff? ? Hook.email_hooks_for_target(@repo) : @repo.email_hooks

      @repo.email_hooks.create(active: true, config: { address: "scope-test@example.com" })
      hook = @repo.repo_hook_associations_ff? ? Hook.email_hooks_for_target(@repo).first : @repo.email_hooks.first
      assert_equal "email", hook.name
      assert_equal "scope-test@example.com", hook.config["address"]
    end
  end

  context "#push_notifications_active?" do
    test "is true with active hook configuration" do
      assert @repo.push_notifications_active?
    end

    test "is false with inactive hook configuration" do
      @email_hook.update(active: false)
      refute @repo.push_notifications_active?
    end

    test "is false with no hook configuration" do
      @email_hook.destroy!
      refute @repo.push_notifications_active?
    end
  end

  context "#transfer_in_progress?" do
    test "is false by default" do
      refute @repo.transfer_in_progress?
    end
  end
end
