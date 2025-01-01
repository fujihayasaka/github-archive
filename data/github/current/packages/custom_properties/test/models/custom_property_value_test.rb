# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertyValueTest < GitHub::TestCase
  fixtures do
    @org = create :enterprise_linked_organization
    @biz = @org.business
    @repo = create :repository, owner: @org
    @definition = create :custom_property_definition, source: @org, property_name: "environment"
    @biz_definition = create :custom_property_definition, source: @biz, property_name: "biz_environment"
  end

  context "save and validate" do
    test "should not save without data" do
      assert_raises ActiveRecord::NotNullViolation do
        CustomPropertyValue.new.save
      end
    end

    test "should not save without target_id" do
      assert_raises ActiveRecord::NotNullViolation do
        CustomPropertyValue.create(
          target_type: "Repository",
          definition_id: @definition.id,
          value: "production"
        )
      end
    end

    test "should save when valid params" do
      assert CustomPropertyValue.create(
        target_id: @repo.id,
        target_type: "Repository",
        definition_id: @definition.id,
        value: "production"
      )
    end
  end

  context "for_target" do
    test "should return values for repository target" do
      create :custom_property_value, definition: @definition, target: @repo, value: "production"
      assert_equal 1, CustomPropertyValue.for_target(@repo).count

      # Org has no values as we haven't saved any value with such target
      assert_equal 0, CustomPropertyValue.for_target(@org).count
    end

    test "should return values for target" do
      create :custom_property_value, definition: @definition, target: @repo, value: "production"
      assert_equal 1, CustomPropertyValue.for_target(@repo).count
    end
  end

  context "instrumentation" do
    [:org, :business].each do |definition_source|
      test "should instrument when a custom_property_value is created for #{definition_source} definition" do
        definition = definition_source == :org ? @definition : @biz_definition
        events = subscribe("custom_property_value.create")
        create :custom_property_value, definition:, target: @repo, value: "production"
        refute_nil event = events.pop, "an event was expected"

        expected_payload = expected_common_payload.merge({
          definition_id: definition.id,
          property_name: definition.property_name,
          value: "production"
        })
        assert_equal expected_payload, event.payload
      end

      test "should instrument when a custom_property_value is destroyed for #{definition_source} definition" do
        definition = definition_source == :org ? @definition : @biz_definition
        property = create :custom_property_value, definition:, target: @repo, value: "production"
        events = subscribe("custom_property_value.destroy")
        property.destroy!

        refute_nil event = events.pop, "an event was expected"

        expected_payload = expected_common_payload.merge({
          definition_id: definition.id,
          property_name: definition.property_name,
          value: "production"
        })
        assert_equal expected_payload, event.payload
      end

      test "should instrument when a custom_property_value is updated for #{definition_source} definition" do
        definition = definition_source == :org ? @definition : @biz_definition
        property = create :custom_property_value, definition:, target: @repo, value: "production"
        events = subscribe("custom_property_value.update")
        property.update!(value: "testing")

        refute_nil event = events.pop, "an event was expected"

        expected_payload = expected_common_payload.merge({
          definition_id: definition.id,
          property_name: definition.property_name,
          value: "testing",
          old_value: "production"
        })
        assert_equal expected_payload, event.payload
      end

      test "should not auditlog when no changes for #{definition_source} definition" do
        definition = definition_source == :org ? @definition : @biz_definition
        property = create :custom_property_value, definition:, target: @repo, value: "production"
        events = subscribe("custom_property.update")

        property.update!(value: "production")

        assert_empty events
      end
    end
  end

  def expected_common_payload
    {
      repo: @repo.name_with_display_owner,
      repo_id: @repo.id,
      org: @org.display_login,
      org_id: @org.id,
      public_repo: true
    }
  end
end
