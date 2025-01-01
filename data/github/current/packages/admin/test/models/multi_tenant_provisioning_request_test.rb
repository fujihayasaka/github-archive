# typed: true
# frozen_string_literal: true

require "test_helper"

class MultiTenantProvisioningRequestTest < GitHub::TestCase
  skip_enterprise
  skip_with_all_emus

  context "validations" do
    test "require that name is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, name: ""

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:name], "can't be blank"
    end

    test "require that name be no longer than 60 characters" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, name: SecureRandom.hex(61)

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:name], "is too long (maximum is 60 characters)"
    end

    test "require that subdomain is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, subdomain: ""

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:subdomain], "can't be blank"
    end

    test "require that subdomain be no longer than 32 characters" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, subdomain: SecureRandom.hex(33)

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:subdomain], "is too long (maximum is 32 characters)"
    end

    test "require that subdomain be of valid format" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, subdomain: "NOT VALID"

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes \
        multi_tenant_provisioning_request.errors[:subdomain],
        "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
    end

    test "require that subdomain cannot contain emojis" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, subdomain: "NEWSPACE-🐹"

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes \
        multi_tenant_provisioning_request.errors[:subdomain],
        "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
    end

    test "require that subdomain is unique" do
      create :multi_tenant_provisioning_request, subdomain: "newspace-inc"
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, subdomain: "newspace-inc"

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:subdomain], "is already taken"
    end

    test "require that subdomain uniqueness is case insensitive" do
      create :multi_tenant_provisioning_request, subdomain: "newspace-inc"
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, subdomain: "NEWSPACE-INC"

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:subdomain], "is already taken"
    end

    test "require that industry is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, industry: ""

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:industry], "must be selected"
    end

    test "require that number of seats is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, number_of_seats: ""

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:number_of_seats], "must be selected"
    end

    test "require that country code is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, country_code: ""

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:country_code], "must be selected"
    end

    test "require that country code be no longer than 3 characters" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, country_code: SecureRandom.hex(4)

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:country_code], "is too long (maximum is 3 characters)"
    end

    test "require that data hosting region is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, data_hosting_region: nil

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:data_hosting_region], "must be selected"
    end

    test "require that data hosting region is a valid option" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, data_hosting_region: :invalid

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:data_hosting_region], "is not included in the list"
    end

    test "data hosting region is prod weu 01 by default" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request

      assert_predicate multi_tenant_provisioning_request, :prod_weu_01?
    end

    test "require that provisioning step is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, provisioning_step: nil

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:provisioning_step], "can't be blank"
    end

    test "require that provisioning step is a valid option" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, provisioning_step: :invalid

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:provisioning_step], "is not included in the list"
    end

    test "provisioning step is requested by default" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request

      assert_predicate multi_tenant_provisioning_request, :requested?
    end

    test "require that admin name is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, admin_name: ""

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:admin_name], "can't be blank"
    end

    test "require that admin name be no longer than 255 characters" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, admin_name: SecureRandom.hex(256)

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:admin_name], "is too long (maximum is 255 characters)"
    end

    test "require that admin work email is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, admin_work_email: ""

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:admin_work_email], "can't be blank"
    end

    test "require that admin work email be no longer than 255 characters" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, \
        admin_work_email: SecureRandom.hex(256)

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes \
        multi_tenant_provisioning_request.errors[:admin_work_email], "is too long (maximum is 255 characters)"
    end

    test "require that EMU IdP is present" do
      multi_tenant_provisioning_request = build :multi_tenant_provisioning_request, emu_idp: nil

      refute_predicate multi_tenant_provisioning_request, :valid?
      assert_includes multi_tenant_provisioning_request.errors[:emu_idp], "must be selected"
    end
  end
end
