# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::BillingContactResultTest < GitHub::TestCase
  test "creates success result from contact data" do
    contact_data = {
      FirstName: "John",
      LastName: "Doe",
    }.stringify_keys

    result = Sponsors::BillingContactResult.success(contact_data)

    assert_predicate result, :success?
    assert_equal contact_data, result.contact_data
  end

  test "creates a failure result from an error" do
    error = "BillToId cannot be blank"

    result = Sponsors::BillingContactResult.error(error)

    assert result.error?
    assert_predicate result, :error?
  end
end
