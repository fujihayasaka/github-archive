# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertyPayloadTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:enterprise_linked_organization, admin: @owner)
    @business = @org.business

    @no_biz_org = create(:organization, admin: @owner)
    @no_biz_org_definition = create :custom_property_definition, source: @no_biz_org, property_name: "env"

    @definition = create :custom_property_definition, source: @org, property_name: "env"
    @biz_definition = create :custom_property_definition, source: @business, property_name: "biz_env"
  end

  [:created, :updated].each do |action|
    test "#{action} payload should include the action, org, enterprise and definition" do
      event = Hook::Event::CustomPropertyEvent.new(
        action: action,
        actor_id: @owner.id,
        org_id: @org.id,
        property_name: @definition.property_name,
        definition_id: @definition.id,
      )
      payload = Hook::Payload::CustomPropertyPayload.new(event).to_hash

      assert_equal payload[:action], action
      assert_equal "env", payload[:definition][:property_name]
      assert_equal "string", payload[:definition][:value_type]
      refute payload[:definition][:required]
      assert_equal "org_actors", payload[:definition][:values_editable_by]
      assert_match(%r(/orgs/#{@org.display_login}/properties/schema/env), payload[:definition][:url])
      assert_equal payload[:organization][:id], @org.id
      assert_equal payload[:enterprise][:id], @org.business.id
    end

    test "enterprise property #{action} payload should include the action, business, and definition" do
      event = Hook::Event::CustomPropertyEvent.new(
        action: action,
        actor_id: @owner.id,
        business_id: @business.id,
        property_name: @biz_definition.property_name,
        definition_id: @biz_definition.id,
      )
      payload = Hook::Payload::CustomPropertyPayload.new(event).to_hash

      assert_equal payload[:action], action
      assert_equal "biz_env", payload[:definition][:property_name]
      assert_equal "string", payload[:definition][:value_type]
      refute payload[:definition][:required]
      assert_equal "org_actors", payload[:definition][:values_editable_by]
      assert_nil payload[:definition][:url]
      refute payload[:organization]
      assert_equal payload[:enterprise][:id], @business.id
    end

    unless GitHub.enterprise?
      test "orgs outside of the enterprise #{action} payload should include the action, org, and definition", skip_with_all_emus: true do
        event = Hook::Event::CustomPropertyEvent.new(
          action: action,
          actor_id: @owner.id,
          org_id: @no_biz_org.id,
          property_name: @no_biz_org_definition.property_name,
          definition_id: @no_biz_org_definition.id,
        )

        payload = Hook::Payload::CustomPropertyPayload.new(event).to_hash

        assert_equal payload[:action], action
        assert_equal "env", payload[:definition][:property_name]
        assert_equal "string", payload[:definition][:value_type]
        refute payload[:definition][:required]
        assert_equal "org_actors", payload[:definition][:values_editable_by]
        assert_match(%r(/orgs/#{@no_biz_org.display_login}/properties/schema/env), payload[:definition][:url])
        assert_equal payload[:organization][:id], @no_biz_org.id
        refute payload[:enterprise]
      end
    end
  end

  test "delete payload should include the action, org, business, and property name" do
    @definition.destroy!
    event = Hook::Event::CustomPropertyEvent.new(
      action: :deleted,
      actor_id: @owner.id,
      org_id: @org.id,
      property_name: @definition.property_name,
      definition_id: @definition.id,
    )

    payload = Hook::Payload::CustomPropertyPayload.new(event).to_hash

    assert_equal payload[:action], :deleted
    assert_equal payload[:definition], { property_name: @definition.property_name }
    assert_equal payload[:organization][:id], @org.id
    assert_equal payload[:enterprise][:id], @business.id
  end

  test "enterprise property delete payload should include the action, business, and property name" do
    @biz_definition.destroy!
    event = Hook::Event::CustomPropertyEvent.new(
      action: :deleted,
      actor_id: @owner.id,
      business_id: @business.id,
      property_name: @biz_definition.property_name,
      definition_id: @biz_definition.id,
    )

    payload = Hook::Payload::CustomPropertyPayload.new(event).to_hash

    assert_equal payload[:action], :deleted
    assert_equal payload[:definition], { property_name: @biz_definition.property_name }
    refute payload[:organization]
    assert_equal payload[:enterprise][:id], @business.id
  end

  unless GitHub.enterprise?
    test "orgs outside of the enterprise delete payload should include the action, org, and definition", skip_with_all_emus: true do
      @no_biz_org_definition.destroy!
      event = Hook::Event::CustomPropertyEvent.new(
        action: :deleted,
        actor_id: @owner.id,
        org_id: @no_biz_org.id,
        property_name: @no_biz_org_definition.property_name,
        definition_id: @no_biz_org_definition.id,
      )

      payload = Hook::Payload::CustomPropertyPayload.new(event).to_hash

      assert_equal payload[:action], :deleted
      assert_equal payload[:definition], { property_name: @no_biz_org_definition.property_name, }
      assert_equal payload[:organization][:id], @no_biz_org.id
      refute payload[:enterprise]
    end
  end
end
