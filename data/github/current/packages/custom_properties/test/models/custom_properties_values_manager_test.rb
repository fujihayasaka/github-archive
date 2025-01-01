# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomPropertiesValuesManagerTest < Api::TestCase
  include CustomProperties
  include CustomProperties::Errors
  include FineGrainedPermissionsTestHelper
  include PerformanceTestHelpers
  include CustomPropertiesTestHelper

  setup do
    @org = create :enterprise_linked_organization
    @biz = @org.business

    GitHub.flipper[:enterprise_custom_properties].enable(@biz)

    @repo = create :repository, owner: @org
    @smile = create :repository, owner: @org

    @manager = Public.values_manager(Public.definitions_manager(@org))
    @definition_env = create :custom_property_definition, source: @org, property_name: "environment"
    @definition_platform = create :custom_property_definition, :multi_select, source: @org
    @definition_security = create :custom_property_definition, source: @org, property_name: "security"
    create :custom_property_definition, :single_select, source: @org, property_name: "cost_center", allowed_values: ["east"]
    @biz_definition_version = create :custom_property_definition, source: @biz, property_name: "biz_version"

    GitHub.flipper[:permission_enforcer_with_caching].disable
  end

  test "should raise if definition's manager source is not an org" do
    exception = assert_raises ArgumentError do
      Public.values_manager(Public.definitions_manager(@biz))
    end

    assert_equal "Only definitions manager initialized with an org is accepted", exception.message
  end

  context "set_properties_for" do
    test "should set and update if record already exists" do
      @manager.set_properties_for([@repo, @smile], { "environment" => "value" }, actor: @org.admin)
      assert_equal repo_properties(@repo, :manual), { "environment" => "value" }
      assert_equal repo_properties(@smile, :manual), { "environment" => "value" }

      @manager.set_properties_for([@repo, @smile], { "environment" => "valueUpdated" }, actor: @org.admin)
      assert_equal repo_properties(@repo, :manual), { "environment" => "valueUpdated" }
      assert_equal repo_properties(@smile, :manual), { "environment" => "valueUpdated" }

      @manager.set_properties_for([@repo], { "environment" => "valueUpdated_again" }, actor: @org.admin)
      assert_equal repo_properties(@repo, :manual), { "environment" => "valueUpdated_again" }
      assert_equal repo_properties(@smile, :manual), { "environment" => "valueUpdated" }

      @manager.set_properties_for([@repo, @smile], { "environment" => nil }, actor: @org.admin)
      assert_empty repo_properties(@repo, :manual)
      assert_empty repo_properties(@smile, :manual)
    end

    test "can set enterprise properties" do
      @manager.set_properties_for([@repo, @smile], { "biz_version" => "1.0" }, actor: @org.admin)

      assert_equal repo_properties(@repo, :manual), { "biz_version" => "1.0" }
      assert_equal repo_properties(@smile, :manual), { "biz_version" => "1.0" }
    end

    test "should remove property if value is string or empty list" do
      @manager.set_properties_for([@repo, @smile], { "environment" => "prod", "platform" => %w(ios) }, actor: @org.admin)
      assert_equal repo_properties(@repo, :manual), { "environment" => "prod", "platform" => %w(ios) }

      @manager.set_properties_for([@repo, @smile], { "environment" => "", "platform" => [] }, actor: @org.admin)
      assert_empty repo_properties(@repo, :manual)
    end

    test "should create, update, delete in a single operation" do
      @manager.set_properties_for([@repo, @smile], { "environment" => "value", "security" => "high" }, actor: @org.admin)
      assert_equal repo_properties(@repo, :manual), { "environment" => "value", "security" => "high" }
      assert_equal repo_properties(@smile, :manual), { "environment" => "value", "security" => "high" }

      @manager.set_properties_for([@repo, @smile], {
        "environment" => nil,     # delete
        "security" => "low",      # update
        "cost_center" => "east",  # create
      }, actor: @org.admin)

      assert_equal repo_properties(@repo, :manual), { "security" => "low", "cost_center" => "east" }
      assert_equal repo_properties(@smile, :manual), { "security" => "low", "cost_center" => "east" }
    end

    test "should raise validation error if properties do not match the schema" do
      exception = assert_raises PropertyValidationError do
        @manager.set_properties_for([@repo], { "invalid_property" => "value" }, actor: @org.admin)
      end

      assert_equal exception.message, "Unexpected property 'invalid_property'"
      assert_equal exception.validation_errors.map(&:property_name), ["invalid_property"]
    end

    test "should raise validation error if properties is of wrong type" do
      wrong_values = [123, true, %w[prod test], { one: "1" }]
      wrong_values.map do |value|
        exception = assert_raises PropertyValidationError do
          @manager.set_properties_for([@repo], { "environment" => value }, actor: @org.admin)
        end
        assert exception.message.start_with?("Property 'environment' values must be strings")
      end
    end

    test "must save with true/false for true_false type" do
      create :custom_property_definition, source: @org, property_name: "true_false", value_type: :true_false

      @manager.set_properties_for([@repo], { "true_false" => "true" }, actor: @org.admin)
      @manager.set_properties_for([@repo], { "true_false" => "false" }, actor: @org.admin)

      exception = assert_raises PropertyValidationError do
        @manager.set_properties_for([@repo], { "true_false" => "notbool" }, actor: @org.admin)
      end

      assert_equal exception.message, "Value 'notbool' is not allowed for property 'true_false'"
    end

    test "should throw on large values" do
      text75 = "a" * 75
      @manager.set_properties_for([@repo], { "environment" => text75 }, actor: @org.admin)

      text76 = "a" * 76
      exception = assert_raises PropertyValidationError do
        @manager.set_properties_for([@repo], { "environment" => text76 }, actor: @org.admin)
      end
      assert_equal "Property 'environment' value is too long", exception.message
    end

    %w{
      any_value
      team#44
      team$one
      https://github.com/my-projects/13?pane=closed%20issues&itemId=2488+2217
      a,b,c;1,2,3
      <my~value>
    }.each do |sample|
      test "can save with allowed characters: #{sample}" do
        assert @manager.set_properties_for([@repo], { "environment" => sample }, actor: @org.admin)
      end
    end

    test "should not save if value has unallowed characters" do
      exception = assert_raises PropertyValidationError do
        @manager.set_properties_for([@repo], { "environment" => "a\"b" }, actor: @org.admin)
      end
      assert_equal "Property 'environment' value has invalid characters: \"", exception.message

      exception = assert_raises PropertyValidationError do
        @manager.set_properties_for([@repo], { "environment" => "a \" 🦦 ゴ" }, actor: @org.admin)
      end
      assert_equal "Property 'environment' value has invalid characters: \", 🦦, ゴ", exception.message

      assert_empty repo_properties(@repo, :manual)
    end

    test "raises exception if repo owner is not org", skip_with_all_emus: true do
      repo = create :repository
      exception = assert_raises TypeError do
        @manager.set_properties_for([repo], { "environment" => "value" }, actor: @org.admin)
      end
      assert exception.message.start_with?("T.cast: Expected type Organization, got type User")
    end

    test "raises exception if repo owner is not the same org" do
      second_org = create :organization
      repo = create :repository, owner: second_org
      exception = assert_raises ArgumentError do
        @manager.set_properties_for([repo], { "environment" => "value" }, actor: @org.admin)
      end
      assert_equal "Invalid entity: repo #{repo} doesn't belong to org #{@org}", exception.message
    end

    test "raises if actor is not provided or nil" do
      bp_org = create(:business_plus_organization)
      bp_org_repo = create(:repository, owner: bp_org)

      assert_raises_with_message(
        EditPropertyPermissionError,
        "Actor doesn't have permissions to edit properties"
      ) do
        Public.values_manager(Public.definitions_manager(bp_org)).set_properties_for([bp_org_repo], { "environment" => "value" }, actor: nil)
      end

      assert_raises_with_message(
        EditPropertyPermissionError,
        "Actor doesn't have permissions to edit properties"
      ) do
        Public.values_manager(Public.definitions_manager(bp_org)).set_properties_for([bp_org_repo], { "environment" => "value" })
      end
    end

    test "raises if actor lacks permissions to edit properties for repo" do
      bp_org = create(:business_plus_organization)
      bp_org_repo = create(:repository, owner: bp_org)
      create :custom_property_definition, source: bp_org, property_name: "environment", values_editable_by: "org_and_repo_actors"

      collaborator = create :user

      assert_raises_with_message(
        EditPropertyPermissionError,
        "Actor doesn't have permissions to edit properties on repo '#{bp_org_repo.name}'"
      ) do
        Public.values_manager(Public.definitions_manager(bp_org)).set_properties_for([bp_org_repo], { "environment" => "value" }, actor: collaborator)
      end
    end

    test "raises if property is not editable by actor" do
      bp_org = create(:business_plus_organization)
      bp_org_repo = create(:repository, owner: bp_org)

      collaborator = create :user
      grant_custom_role(user: collaborator, target: bp_org_repo, fgps: [:edit_repo_custom_properties_values])
      create :custom_property_definition, source: bp_org, property_name: "org_admin_only", values_editable_by: "org_actors"

      assert_raises_with_message(
        EditPropertyPermissionError,
        "Actor doesn't have permissions to edit properties [org_admin_only]"
      ) do
        Public.values_manager(Public.definitions_manager(bp_org)).set_properties_for([bp_org_repo], { "org_admin_only" => "value" }, actor: collaborator)
      end
    end

    test "should reindex repo with new custom properties" do
      assert_enqueued_jobs 2, only: AddToSearchIndexJob do
        @manager.set_properties_for([@repo, @smile], { "environment" => "reindex" }, actor: @org.admin)
      end
    end

    test "should not reindex if update for one of the repos fails" do
      assert_no_enqueued_jobs do
        assert_raises PropertyValidationError do
          @manager.set_properties_for([@repo, @smile], { "environment" => "invalid\"value" }, actor: @org.admin)
        end
      end
    end

    test "should run SQL queries" do
      assert_query_count_per_table({
        custom_property_definitions: 1,
        custom_property_values: 3 # 1 select + 2 insert
        }) do
          @manager.set_properties_for([@repo, @smile], { "environment" => "production" }, actor: @org.admin)
        end
    end

    test "should not write in DB if values do not changed" do
      create :custom_property_value, definition: @definition_env, target: @repo, value: "production"

      assert_query_count_per_table({
        custom_property_definitions: 1,
        custom_property_values: 2 # 1 select + 1 insert
        }) do
          @manager.set_properties_for([@repo, @smile], { "environment" => "production" }, actor: @org.admin)
        end
    end

    context "instrumentation" do
      test "should instrument for a single repo" do
        create :custom_property_definition, source: @org, property_name: "language"
        @manager.set_properties_for([@repo], { "environment" => "value", "security" => "high", "language" => "ruby", "platform" => %w(ios web) }, actor: @org.admin)
        events = subscribe("repo.update_custom_property_values")

        @manager.set_properties_for([@repo], {
          "environment" => nil,           # delete
          "security" => "low",            # update
          "platform" => %w(android web),  # update
          "cost_center" => "east",        # create
          "language" => "ruby",           # noop
        }, actor: @org.admin)

        refute_nil event = events.pop, "an event was expected"
        payload = event.payload

        assert_equal payload[:repo_id], @repo.id
        assert_equal payload[:org_id], @org.id
        assert_equal payload[:new_values], {
          "environment" => nil,
          "security" => "low",
          "cost_center" => "east",
          "language" => "ruby",
          "platform" => %w(android web),
        }
        assert_equal payload[:old_values], {
          "environment" => "value",
          "security" => "high",
          "cost_center" => nil,
          "language" => "ruby",
          "platform" => %w(ios web),
        }
      end

      test "should instrument create for multiple repos" do
        @manager.set_properties_for([@repo, @smile], { "environment" => "value", "security" => "high" }, actor: @org.admin)
        events = subscribe("repo.update_custom_property_values")

        @manager.set_properties_for([@repo, @smile], { "security" => "low" }, actor: @org.admin)

        assert_equal events.count, 2
        event_repos_id = events.map { |event| event.payload[:repo_id] }
        assert_same_elements event_repos_id, [@repo.id, @smile.id]
      end

      test "should instrument create for business properties and log at the org level" do
        @manager.set_properties_for([@repo, @smile], { "biz_version" => "1.0" }, actor: @org.admin)
        events = subscribe("repo.update_custom_property_values")

        @manager.set_properties_for([@repo, @smile], { "biz_version" => "2.0" }, actor: @org.admin)

        assert_equal events.count, 2
        event_repos_id = events.map { |event| event.payload[:repo_id] }
        assert_same_elements event_repos_id, [@repo.id, @smile.id]

        event_org_id = events.map { |event| event.payload[:org_id] }
        assert_same_elements event_org_id, [@repo.owner.id, @smile.owner.id]
      end

      test "should instrument when nil value" do
        events = subscribe("repo.update_custom_property_values")

        @manager.set_properties_for([@repo], { "environment" => "value", "security" => nil }, actor: @org.admin)

        refute_nil event = events.pop, "an event was expected"
        payload = event.payload

        assert_equal payload[:repo_id], @repo.id
        assert_equal payload[:org_id], @org.id
        assert_equal payload[:new_values], { "environment" => "value", "security" => nil }
        assert_equal payload[:old_values], { "environment" => nil, "security" => nil }
      end

      test "should not instrument if no properties" do
        events = subscribe("repo.update_custom_property_values")

        @manager.set_properties_for([@repo], {}, actor: @org.admin)

        assert_nil event = events.pop
      end
    end
  end

  context "validate_properties" do
    test "should return empty list if no errors" do
      assert_equal @manager.validate_properties({ "cost_center" => "east" }), []
    end

    test "should return errors if property does not exist" do
      errors = @manager.validate_properties({ "unknown" => "planet" })

      assert_equal errors.length, 1
      assert_equal T.must(errors[0]).property_name, "unknown"
      assert_equal T.must(errors[0]).error_message, "Unexpected property 'unknown'"
    end

    test "should return errors if symbols used as hash keys" do
      errors = @manager.validate_properties({ "unknown": "planet" })

      assert_equal errors.length, 1
      assert_equal T.must(errors[0]).property_name, "unknown"
      assert_equal T.must(errors[0]).error_message, "Unexpected property 'unknown'"
    end
  end

  context "check_edit_permissions!" do
    test "batches authzd calls" do
      bp_org = create(:business_plus_organization)
      bp_org_repo_a = create(:repository, owner: bp_org)
      bp_org_repo_b = create(:repository, owner: bp_org)

      collaborator = create :user
      grant_custom_role(user: collaborator, target: bp_org_repo_a, fgps: [:edit_repo_custom_properties_values])
      grant_custom_role(user: collaborator, target: bp_org_repo_b, fgps: [:edit_repo_custom_properties_values])
      create :custom_property_definition, source: bp_org, property_name: "env", values_editable_by: "org_and_repo_actors"

      assert_authzd_calls(single: 0, batch: 1) do
        Public.values_manager(Public.definitions_manager(bp_org)).check_edit_permissions!(collaborator, [bp_org_repo_a, bp_org_repo_b], { "env" => "value" })
      end
    end
  end
end
