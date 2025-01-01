# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOIDCSubClaimTemplateTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    # @org = create(:organization, admin: @admin)
    @template1 = OrganizationOIDCSubClaimTemplate.new(organization_id: 1, template: "template1")
    @template2 = OrganizationOIDCSubClaimTemplate.new(organization_id: 2, template: "template2")
    @template3 = OrganizationOIDCSubClaimTemplate.new(organization_id: 3, template: "template3")

    @template1.save
    @template2.save
    @template3.save

  end

  context "db" do

    # Test if we have three seeded templates
    test "Sanity" do
      # Ensuring we have 3 records to start with
      assert(!@template1.new_record?, "template1 is not saved")
      assert(!@template2.new_record?, "template2 is not saved")
      assert(!@template3.new_record?, "template3 is not saved")
    end

    # Test the fetched entity
    test "Record fetch" do
      sut = OrganizationOIDCSubClaimTemplate.get_template_for_org(2)
      assert_equal(@template2, sut)
      assert_equal sut.template, "template2", "Invalid organization_id"
    end

    # Test record update
    test "Record update" do
      # since the record already exists, it should not be created again but updated
      OrganizationOIDCSubClaimTemplate.create_or_update_template(2, "updatedtemplate")
      # fetch the updates
      sut = OrganizationOIDCSubClaimTemplate.get_template_for_org(2)
      assert_equal sut.template, "updatedtemplate", "Invalid template"
    end

    # Test new record
    test "New Record" do
      # If record does not exist, it should be created
      assert_equal OrganizationOIDCSubClaimTemplate.count, 3, "Unexpected record count"
      OrganizationOIDCSubClaimTemplate.create_or_update_template(10, "newtemplate")
      # count must be +1
      assert_equal OrganizationOIDCSubClaimTemplate.count, 4, "Unexpected record count"
    end

    # Test missing template
    test "No record" do
      sut = OrganizationOIDCSubClaimTemplate.get_template_for_org(1000)
      assert_nil sut, "Expected nil"
    end

  end
end
