# typed: true
# frozen_string_literal: true
require "test_helper"

class SpamDatasourceTest < GitHub::TestCase
  test "#human_name capitalizes each word" do
    q = SpamDatasource.new name: "blacklisted_addresses"
    assert_equal "Blacklisted Addresses", q.human_name
  end

  test "#name= normalizes input" do
    [
      "New User Bad Emails",
      "new_user_bad_emails",
      :new_user_bad_emails,
    ].each do |user_entered_name|
      q = SpamDatasource.new(name: user_entered_name)
      assert_equal "new_user_bad_emails", q.name
    end
  end
end
