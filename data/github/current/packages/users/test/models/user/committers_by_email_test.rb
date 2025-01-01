# typed: true
# frozen_string_literal: true

require "test_helper"

class UserCommittersByEmailTest < GitHub::TestCase
  fixtures do
    @janedoe = create(:user, login: "janedoe", email: "janedoe@example.com")
    @john_with_many_emails = create(:user, login: "john", email: "john1@example.com")
    create(:user_email, user: @john_with_many_emails, email: "john2@example.com")
  end

  test "no matches returns an empty hash" do
    assert_equal Hash.new, User::CommittersByEmail.find(["unknown@example.com"])
  end

  test "getting a single user via email" do
    email = "janedoe@example.com"
    committers = User::CommittersByEmail.find([email])
    assert_equal @janedoe, committers[email]
  end

  test "getting a single user with multiple emails" do
    emails = ["john1@example.com", "john2@example.com"]
    committers = User::CommittersByEmail.find([emails])
    assert_equal @john_with_many_emails, committers["john1@example.com"]
    assert_equal @john_with_many_emails, committers["john2@example.com"]
  end

  test "getting multiple users" do
    emails = ["john1@example.com", "janedoe@example.com"]
    committers = User::CommittersByEmail.find([emails])
    assert_equal 2, committers.values.size
    assert_equal @janedoe, committers["janedoe@example.com"]
    assert_equal @john_with_many_emails, committers["john1@example.com"]
  end

  test "multiple users with an unknown email in the mix" do
    emails = ["john1@example.com", "unknown@example.com", "janedoe@example.com"]
    committers = User::CommittersByEmail.find([emails])
    assert_equal 2, committers.values.size
  end
end
