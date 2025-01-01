# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ContactUpdateStashTest < GitHub::TestCase
  setup do
    @customer = create(:customer)
    @user = create(:user, customer: @customer)
    @params = ActionController::Parameters.new(
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name,
      address1: Faker::Address.street_address,
      address2: Faker::Address.secondary_address,
    )
    @errors = ActiveModel::Errors.new(@user)
    @errors.add(:first_name, "is invalid")

    @user.billing_contact.errors.add(:address1, "is invalid")
    @user.shipping_contact.errors.add(:address1, "is invalid")
  end

  %w[shipping billing].each do |address_type|
    test "stores param and error arguments for #{address_type} information" do
      Billing::ContactUpdateStash.stash_update_for(@user, address_type, @params, @errors)
      stash = Billing::ContactUpdateStash.retrieve_stashed_update_for(@user, address_type)

      assert stash.is_a?(Billing::ContactUpdateStash)
      assert_equal @params["first_name"], stash.field_value("first_name")
      assert_equal @params["last_name"], stash.field_value("last_name")
      assert stash.errors?

      first_name_attributes = {
        value: @params["first_name"],
        validation_message: "First name is invalid",
        aria: { invalid: true },
      }

      last_name_attributes = {
        value: @params["last_name"],
      }

      assert_equal first_name_attributes, stash.primer_form_attributes_for("first_name")
      assert_equal last_name_attributes, stash.primer_form_attributes_for("last_name")
    end

    test "stores params and model errors for #{address_type} information" do
      Billing::ContactUpdateStash.stash_update_for(@user, address_type, @params)
      stash = Billing::ContactUpdateStash.retrieve_stashed_update_for(@user, address_type)

      assert stash.is_a?(Billing::ContactUpdateStash)
      assert_equal @params["address1"], stash.field_value("address1")
      assert_equal @params["address2"], stash.field_value("address2")
      assert stash.errors?

      address1_attributes = {
        value: @params["address1"],
        validation_message: "Address is invalid",
        aria: { invalid: true },
      }

      address2_attributes = {
        value: @params["address2"],
      }

      assert_equal address1_attributes, stash.primer_form_attributes_for("address1")
      assert_equal address2_attributes, stash.primer_form_attributes_for("address2")
    end

    test "attributes are empty when field not present #{address_type} information" do
      user = create(:user)

      Billing::ContactUpdateStash.stash_update_for(user, address_type, @params)
      stash = Billing::ContactUpdateStash.retrieve_stashed_update_for(user, address_type)

      refute stash.errors?
      assert_nil stash.field_value("not_present")
      assert_empty stash.primer_form_attributes_for("not_present")
    end
  end

  test "empty stash has no params or errors" do
    stash = Billing::ContactUpdateStash.empty

    assert_empty stash.send(:data)
  end
end
