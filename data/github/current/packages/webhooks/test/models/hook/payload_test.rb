# typed: ignore
# frozen_string_literal: true

require "test_helper"

class HookPayloadTest < GitHub::TestCase
  class Hook::Event::PayloadTestEvent < Hook::Event
    event_attr :action, :target_repository, :target_organization, :target_business, :actor
  end

  class Hook::Payload::PayloadTestPayload < Hook::Payload
    def to_payload_hash
      {
        action: hook_event.action,
        message: payload_message,
      }
    end

    def payload_message
      "hello world"
    end
  end

  class PayloadHydrationError < StandardError; end

  class Hook::Payload::PayloadTestPayloadWithHydrationError < Hook::Payload
    def to_payload_hash
      raise PayloadHydrationError, "test"
    end
  end

  fixtures do
    @repo = create(:repository)
    @org = create(:organization)
    @business = create(:business)
    @user = create(:user)
  end

  context ".for_event" do
    test "initializes the proper payload model for the event" do
      event = Hook::Event::PayloadTestEvent.new
      payload = Hook::Payload.for_event(event)

      assert payload.instance_of?(Hook::Payload::PayloadTestPayload)
    end

    test "initializes the payload model with the event" do
      event = Hook::Event::PayloadTestEvent.new
      payload = Hook::Payload.for_event(event)

      assert_equal event, payload.hook_event
    end
  end

  context "#to_hash" do
    test "is evaluated against the payload instance" do
      event = Hook::Event::PayloadTestEvent.new action: "created"
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      assert_equal "created", version_hash[:action]
      assert_equal "hello world", version_hash[:message]
    end

    test "doesn't include default payload keys if not supplied" do
      event = Hook::Event::PayloadTestEvent.new target_repository: nil, target_organization: nil, actor: nil
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      refute version_hash.key?(:repository)
      refute version_hash.key?(:organization)
      refute version_hash.key?(:business)
      refute version_hash.key?(:sender)
    end

    test "includes the serialized repository if target_repository is given" do
      event = Hook::Event::PayloadTestEvent.new target_repository: @repo
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      assert_equal @repo.id, version_hash[:repository][:id]
      assert_equal @repo.name, version_hash[:repository][:name]
    end

    test "includes the serialized organization if target_organization is given" do
      event = Hook::Event::PayloadTestEvent.new target_organization: @org
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      assert_equal @org.id, version_hash[:organization][:id]
      assert_equal @org.login, version_hash[:organization][:login]
    end

    test "includes the serialized business (with the 'enterprise' label) if target_business is given" do
      event = Hook::Event::PayloadTestEvent.new target_business: @business, actor: @user
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      assert_equal @business.id, version_hash[:enterprise][:id]
      assert_equal @business.slug, version_hash[:enterprise][:slug]
    end

    test "includes the serialized actor if actor is given" do
      event = Hook::Event::PayloadTestEvent.new actor: @user
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      assert_equal @user.id, version_hash[:sender][:id]
      assert_equal @user.login, version_hash[:sender][:login]
    end

    test "computed versions are immutable" do
      event = Hook::Event::PayloadTestEvent.new action: "created"
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      assert version_hash.frozen?

      assert_raises FrozenError do
        version_hash[:action] = "updated"
      end
    end

    test "uses display_login by default for webhook payload in multi-tenant environment" do
      on_multi_tenant_enterprise do
        emu = create(:emu)
        event = Hook::Event::PayloadTestEvent.new actor: emu
        payload = Hook::Payload::PayloadTestPayload.new event
        version_hash = payload.to_hash

        refute_equal emu.login, emu.display_login
        assert_equal emu.display_login, emu.login_for_api
        assert_equal emu.display_login, version_hash[:sender][:login]
      end
    end

    test "instruments time taken to generate payload" do
      GitHub::MysqlInstrumenter.reset_stats
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      event = Hook::Event::PayloadTestEvent.new target_organization: @org, actor: @user
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      tags = ["event:hook/payload_test", "event_type:hook/payload_test"]
      metrics = GitHub.dogstats.distributions("hooks.payload.apply", tags: tags)

      assert_equal 1, metrics.size

      event = Hook::Event::PayloadTestEvent.new target_organization: @org, actor: @user, action: :event_action
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash

      tags = ["event:hook/payload_test_event_action", "event_type:hook/payload_test"]
      metrics = GitHub.dogstats.distributions("hooks.payload.apply", tags: tags)

      assert_equal 1, metrics.size
    end

    test "counts the number of queries during hydration with feature flag enabled" do
      GitHub::MysqlInstrumenter.reset_stats
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      GitHub.flipper[:webhooks_payload_query_counts].enable

      event = Hook::Event::PayloadTestEvent.new target_organization: @org, actor: @user
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash
      metrics = GitHub.dogstats.distributions("hook.event.payload.queries")

      assert_equal 1, metrics.size
      assert_equal 3, metrics.first.value
    end

    test "does not count the number of queries during hydration with feature flag disabled" do
      GitHub::MysqlInstrumenter.reset_stats
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      GitHub.flipper[:webhooks_payload_query_counts].disable

      event = Hook::Event::PayloadTestEvent.new target_organization: @org, actor: @user
      payload = Hook::Payload::PayloadTestPayload.new event
      version_hash = payload.to_hash
      metrics = GitHub.dogstats.distributions("hook.event.payload.queries")
      assert_equal 0, metrics.size
    end

    test "increments metric and raises error if error is encountered during payload hydration" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      event = Hook::Event::PayloadTestEvent.new target_organization: @org, actor: @user
      payload = Hook::Payload::PayloadTestPayloadWithHydrationError.new event
      assert_raises PayloadHydrationError do
        payload.to_hash
      end
      tags = ["event:hook/payload_test", "event_type:hook/payload_test", "exception_class:hook_payload_test/payload_hydration_error"]
      assert_equal 1, GitHub.dogstats.increments("hooks.payload_hydration.error", tags: tags).count
    end

    test "does not increment metric and raises error if error is not encountered during payload hydration" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      event = Hook::Event::PayloadTestEvent.new target_organization: @org, actor: @user
      payload = Hook::Payload::PayloadTestPayload.new event
      payload.to_hash
      assert_equal 0, GitHub.dogstats.increments("hooks.payload_hydration.error").count
    end

    context "custom properties" do
      test "includes custom properties" do
        admin = create :user
        org = create :organization, admin: admin
        org_repo = create :repository, owner: org

        create :custom_property_definition, source: org, property_name: "env", required: true, default_value: "prod"
        language_definition = create :custom_property_definition, source: org, property_name: "language"
        create :custom_property_value, definition: language_definition, target: org_repo, value: "ruby"

        event = Hook::Event::PayloadTestEvent.new target_repository: org_repo, actor: admin
        payload = Hook::Payload::PayloadTestPayload.new event
        version_hash = payload.to_hash

        assert_equal org_repo.id, version_hash[:repository][:id]
        assert_equal org_repo.name, version_hash[:repository][:name]
        assert_equal version_hash[:repository][:custom_properties], { language: "ruby", env: "prod" }
      end

      test "include empty custom properties when no definitions created" do
        admin = create :user
        org = create :organization, admin: admin
        org_repo = create :repository, owner: org

        event = Hook::Event::PayloadTestEvent.new target_repository: org_repo, actor: admin
        payload = Hook::Payload::PayloadTestPayload.new event
        version_hash = payload.to_hash

        assert version_hash.key?(:repository)
        assert_empty version_hash[:repository][:custom_properties]
      end

      test "do not include custom_properties when repo not part of an org" do
        event = Hook::Event::PayloadTestEvent.new target_repository: @repo, actor: @repo.owner
        payload = Hook::Payload::PayloadTestPayload.new event
        version_hash = payload.to_hash

        assert version_hash.key?(:repository)
        refute version_hash[:repository].key?(:custom_properties)
      end
    end
  end
end
