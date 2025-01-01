# typed: true
# frozen_string_literal: true
require "test_helper"

class StafftoolsAccessControlLinterTest < GitHub::TestCase
  fixtures do
    @staff = create :staff_admin_user
    @controllers = Stafftools::AccessControl.permissions["controllers"]
    @actions = @controllers.collect { |controller| controller["actions"] }.flatten.compact
    @valid_config_roles = [
      "*",
      "can-add-email",
      "can-deprovision-codespaces",
      "can-disable-2fa",
      "can-impersonate-users",
      "can-impersonate-users-without-permission",
      "can-unlock-repos-with-owners-permission",
      "can-unlock-repos-without-owners-permission",
      "can-unreserve-login",
      "can-execute-trade-controls",
      "can-view-trade-controls",
      "developer",
      "read-only",
      "super-admin",
      "support",
      "support-contractors",
    ]
    @valid_stafftools_roles = (@valid_config_roles - ["*"])
  end

  setup do
    hash_entries = @valid_stafftools_roles.map do |role_name|
      [role_name, StafftoolsRole.create(name: role_name)]
    end
    @stafftools_roles = Hash[hash_entries]
  end

  context "linting stafftools_permissions.yml located in config" do
    test "name and allowed_roles are present for each controller" do
      @controllers.each do |controller|
        assert controller["name"].present?,
          message_wrapper("Controller \"name\" attribute not specified - #{controller}")
        assert controller["allowed_roles"].present?,
          message_wrapper("Controller \"allowed_roles\" attribute not specified  - #{controller}")
      end
    end

    test "controller allowed_roles is composed of valid roles" do
      @controllers.each do |controller|
        assert_valid_roles(controller["allowed_roles"])
      end
    end

    test "name and (allowed_roles_override or excluded_roles) are present for each action" do
      @actions.each do |action|
        assert action["name"].present?, "Action name not specified"
        assert (action["allowed_roles_override"].present? || action["excluded_roles"].present?),
          message_wrapper("Action allowed_roles_override or excluded_roles not specified - #{action}")
      end
    end

    test "action allowed_roles_override is composed of valid roles" do
      override_roles = @actions.collect do |action|
        action["allowed_roles_override"]
      end.flatten.compact
      assert_valid_roles(override_roles)
    end

    test "action excluded_roles is composed of valid roles" do
      excluded_roles = @actions.collect do |action|
        action["excluded_roles"]
      end.flatten.compact
      assert_valid_roles(excluded_roles)
    end

    test "check that controllers exist" do
      @controllers.each do |controller|
        assert_valid_controller(controller["name"])
      end
    end

    test "check that controller actions exist" do
      @controllers.each do |controller|
        if controller["actions"].present?
          controller["actions"].each do |action|
            assert_valid_controller_and_action(controller["name"], action["name"])
          end
        end
      end
    end
  end

  context "verifying controller and action authorized roles", skip_enterprise: true do
    test "authorized roles for Stafftools::SearchIndexesController#index" do
      allowed_roles = %w[super-admin developer]
      assert_authorized("Stafftools::SearchIndexesController", "index",
        allowed_roles)
      assert_not_authorized("Stafftools::SearchIndexesController", "index",
        @valid_stafftools_roles - allowed_roles)
    end

    test "authorized roles for Stafftools::SessionsController#impersonate" do
      allowed_roles = ["can-impersonate-users"]
      assert_authorized("Stafftools::SessionsController", "impersonate",
        allowed_roles)
      assert_not_authorized("Stafftools::SessionsController", "impersonate",
        @valid_stafftools_roles - allowed_roles)
    end

    test "authorized roles for Stafftools::Users::SearchRecords::ReindexRequestsController#create" do
      excluded_roles = ["read-only"]
      assert_authorized("Stafftools::Users::SearchRecords::ReindexRequestsController", "create",
        @valid_stafftools_roles - excluded_roles)
      assert_not_authorized("Stafftools::Users::SearchRecords::ReindexRequestsController", "create",
       excluded_roles)
    end

    test "authorized roles for Stafftools::Users::SiteAdminsController#create" do
      allowed_roles = ["super-admin"]
      assert_authorized("Stafftools::Users::SiteAdminsController", "create",
        allowed_roles)
      assert_not_authorized("Stafftools::Users::SiteAdminsController", "create",
        @valid_stafftools_roles - allowed_roles)
    end
  end

  context "verify the assertion helpers" do
    test "valid controller succeeds" do
      assert_valid_controller("StafftoolsController")
    end

    test "invalid controller raises NameError" do
      assert_raises Minitest::Assertion do
        assert_valid_controller("ControllerThatDoesNotExistController")
      end
    end

    test "valid controller and action succeed" do
      assert_valid_controller_and_action("StafftoolsController", "index")
    end

    test "valid controller with invalid action raises Minitest::Assertion" do
      assert_raises Minitest::Assertion do
        assert_valid_controller_and_action("StafftoolsController", "bad_action_name")
      end
    end

    test "valid roles succeed" do
      roles = ["*", "developer", "read-only"]
      assert_valid_roles(roles)
    end

    test "invalid roles raise Minitest::Assertion" do
      roles = ["*", "super-duper-admin", "read-only"]
      assert_raises Minitest::Assertion do
        assert_valid_roles(roles)
      end
    end
  end

  ##
  # Assertion helpers
  ##

  def assert_valid_controller(controller)
    begin
      # constantize controller names, raises NameError if controller does not exist
      assert controller.constantize
    rescue NameError => e
      raise Minitest::Assertion, message_wrapper("Cannot find controller named #{controller}")
    end
  end

  def assert_valid_controller_and_action(controller, action)
    assert_valid_controller(controller)
    assert controller.constantize.instance_methods.include?(action.to_sym),
      message_wrapper("Action \"#{action}\" does not exist for controller #{controller}")
  end

  def assert_valid_roles(roles)
    roles.each do |role|
      assert @valid_config_roles.include?(role),
        message_wrapper("Invalid role specified: #{role} - found in #{roles}")
    end
  end

  def assert_authorized(controller, action, role_names)
    role_names.each do |role_name|
      add_role_to_staff(role_name)
      assert_valid_controller_and_action(controller, action)
      assert Stafftools::AccessControl.authorized?(@staff,
        { controller: controller, action: action }),
        message_wrapper("#{controller}##{action} does not allow role \"#{role_name}\", this is not expected")
      remove_roles_from_staff
    end
  end

  def assert_not_authorized(controller, action, role_names)
    role_names.each do |role_name|
      add_role_to_staff(role_name)
      assert_valid_controller_and_action(controller, action)
      refute Stafftools::AccessControl.authorized?(@staff,
        { controller: controller, action: action }),
        message_wrapper("#{controller}##{action} allows role \"#{role_name}\", this is not expected")
      remove_roles_from_staff
    end
  end

  ##
  # Setup helpers
  ##

  def add_role_to_staff(role_name)
    @staff.stafftools_roles << @stafftools_roles[role_name]
    @staff.save
  end

  def remove_roles_from_staff
    @staff.stafftools_roles = []
    @staff.save
  end

  ##
  # Message helpers
  ##

  def message_wrapper(message)
    %{
      **************************************************************
      *
      *   #{message}
      *
      **************************************************************
    }
  end
end
