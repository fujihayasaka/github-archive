# typed: false
# frozen_string_literal: true

require "test_helper"

class ExternalIdentityAttributeAssociationExtensionTest < GitHub::TestCase
  fixtures do
    @external_identity = create :external_identity
    @external_identity.identity_attribute_records.destroy_all

    @external_identity.identity_attribute_records.create! \
      scheme: :saml,
      name: "name_id",
      value: "mtodd"
    @external_identity.identity_attribute_records.create! \
      scheme: :scim,
      name: "userName",
      value: "mtodd"
    @external_identity.identity_attribute_records.create! \
      scheme: :scim,
      name: "emails",
      value: "mtodd@github.com",
      metadata: {
        "type" => "work",
      }
    @external_identity.identity_attribute_records.create! \
      scheme: :scim,
      name: "emails",
      value: "matt.todd@github.com",
      metadata: {
        "primary" => true,
        "type" => "work",
      }
  end

  context "#attributes_by_scheme" do
    test "returns an array of attributes for a given scheme" do
      expected = [
        {
          "name" => "userName",
          "value" => "mtodd",
          "metadata" => {},
        },
        {
          "name" => "emails",
          "value" => "mtodd@github.com",
          "metadata" => { "type" => "work" },
        },
        {
          "name" => "emails",
          "value" => "matt.todd@github.com",
          "metadata" => { "type" => "work", "primary" => true },
        },
      ]

      assert_same_elements expected, @external_identity.identity_attribute_records.attributes_by_scheme[:scim]
    end

    test "filters out any attributes that will be deleted when the record is saved" do
      name_id = @external_identity.identity_attribute_records.detect do |attr|
        attr.scheme == "saml" && attr.name == "name_id"
      end

      refute_empty @external_identity.identity_attribute_records.attributes_by_scheme[:saml]

      name_id.mark_for_destruction
      assert_empty @external_identity.identity_attribute_records.attributes_by_scheme[:saml]
    end
  end

  context "#set_scheme_attributes=" do
    test "builds backing identity attribute records" do
      external_identity = ExternalIdentity.new
      external_identity.identity_attribute_records.set_scheme_attributes(:saml, [
        { "name" => "name_id", "value" => "mtodd" },
      ])

      assert attribute = external_identity.identity_attribute_records.first

      refute_predicate attribute, :persisted?
      assert_equal "name_id", attribute.name
      assert_equal "mtodd", attribute.value
    end

    test "adds new identity attribute records" do
      @external_identity.identity_attribute_records.set_scheme_attributes(:saml, [
        { "name" => "name_id", "value" => "mtodd" },
        { "name" => "first_name", "value" => "Matt" },
      ])

      assert attribute = @external_identity.identity_attribute_records.detect(&:new_record?)
      assert_equal "saml", attribute.scheme.to_s
      assert_equal "first_name", attribute.name
      assert_equal "Matt", attribute.value
    end

    test "marks existing unspecified records for destruction" do
      @external_identity.identity_attribute_records.set_scheme_attributes(:saml, [
        { "name" => "first_name", "value" => "Matt" },
      ])

      assert attribute = @external_identity.identity_attribute_records.detect(&:marked_for_destruction?)
      assert_equal "saml", attribute.scheme.to_s
      assert_equal "name_id", attribute.name
    end

    test "updates metadata on existing records" do
      @external_identity.identity_attribute_records.set_scheme_attributes(:scim, [
        { "name" => "userName", "value" => "mtodd" },
        { "name" => "emails", "value" => "mtodd@github.com", "metadata" => { "type" => "home" } },
      ])

      assert attribute = @external_identity.identity_attribute_records.detect(&:changed?)
      assert_predicate attribute, :persisted?
      assert_equal "scim", attribute.scheme.to_s
      assert_equal "emails", attribute.name
      assert_equal "mtodd@github.com", attribute.value
      assert_equal "home", attribute.metadata["type"]
    end

    test "ignores attributes with no name" do
      @external_identity.identity_attribute_records.set_scheme_attributes(:saml, [
        { "name" => "", "value" => "mtodd" },
      ])

      assert_empty @external_identity.identity_attribute_records.attributes_by_scheme[:saml]
    end

    test "ignores attributes with no value" do
      @external_identity.identity_attribute_records.set_scheme_attributes(:saml, [
        { "name" => "name_id", "value" => "" },
      ])

      assert_empty @external_identity.identity_attribute_records.attributes_by_scheme[:saml]
    end
  end
end
