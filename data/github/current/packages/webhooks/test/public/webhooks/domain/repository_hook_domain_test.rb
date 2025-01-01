# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryHookDomainTest < GitHub::TestCase
  fixtures do
    @mojombo = create(:user, login: "mojombo", plan: "medium")

    @repo = create(:repository, name: "grit", owner: @mojombo)
    @push = create(:push, {
      repository: @repo,
      pusher: @mojombo,
      ref: "refs/heads/my-branch",
      before: "0000000000000000000000000000000000000000",
      after: "63611721afd41f58f801d66e543d8288b4c5eb44",
    })
    @hook = create :hook, installation_target: @repo, active: true, events: %w(push)
    @email_hook = create(:hook, name: "email", active: true, events: ["push"], installation_target: @repo, config: { address: "foo@example.com " })
  end

  setup do
    @domain = Webhooks::Domain.new(:test)
  end

  context "when there is a push record to reference" do
    test "it creates a Hook::Event::PushEvent with the push details" do
      current_time = Time.now
      expected_arguments = {
        target_hook: @hook,
        repo: @repo,
        pusher: @mojombo,
        ref: "refs/heads/my-branch",
        before: "0000000000000000000000000000000000000000",
        after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        triggered_at: current_time,
      }
      event = Hook::Event::PushEvent.new(expected_arguments)
      Timecop.freeze(current_time) do
        Hook::Event::PushEvent.expects(:new).with(expected_arguments).returns(event)
        @domain.send_test_webhook(hook: @hook)
      end
    end
  end

  context "#push_notifications_active?" do
    test "is true with active hook configuration" do
      assert @domain.push_notifications_active?(repository_id: @repo.id)
    end

    test "is false with inactive hook configuration" do
      @email_hook.update(active: false)
      refute @domain.push_notifications_active?(repository_id: @repo.id)
    end

    test "is false with no hook configuration" do
      @email_hook.destroy!
      refute @domain.push_notifications_active?(repository_id: @repo.id)
    end
  end
end
