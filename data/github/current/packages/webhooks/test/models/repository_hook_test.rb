# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryHookTest < GitHub::TestCase
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
  end

  setup do
    @webhooks_domain = Webhooks::Domain.new
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
        @webhooks_domain.send_test_webhook(hook: @hook)
      end
    end
  end

  context "when there is no push record to reference" do
    test "no Hook::Event::PushEvent is created" do
      Hook::Event::PushEvent.expects(:new).never
      Hook::DeliverySystem.any_instance.expects(:generate_hookshot_payloads).never

      @push.destroy
      @webhooks_domain.send_test_webhook(hook: @hook)
    end
  end
end
