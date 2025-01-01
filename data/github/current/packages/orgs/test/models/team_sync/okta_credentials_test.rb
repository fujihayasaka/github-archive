# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamSync::OktaCredentialsTest < GitHub::TestCase
  test "#valid? returns true when ssws_token and url are present" do
    okta_credentials = TeamSync::OktaCredentials.new(ssws_token: "fake-token", url: "https://www.example.com")

    assert_predicate okta_credentials, :valid?
  end

  test "#valid? returns false when ssws_token is missing" do
    okta_credentials = TeamSync::OktaCredentials.new(ssws_token: nil, url: "https://www.example.com")

    refute_predicate okta_credentials, :valid?
    assert_match(/blank/, okta_credentials.errors[:ssws_token].join(" "))
  end

  test "#valid? returns false when url is missing" do
    okta_credentials = TeamSync::OktaCredentials.new(ssws_token: "fake-token", url: nil)

    refute_predicate okta_credentials, :valid?
    assert_match(/blank/, okta_credentials.errors[:url].join(" "))
  end

  test "#valid? ensures URLs is valid" do
    okta_credentials = TeamSync::OktaCredentials.new(ssws_token: "fake-token", url: "http://www.example.com/abc?q=badurl")

    refute_predicate okta_credentials, :valid?
    assert_match(/query/, okta_credentials.errors[:url].join(" "))
    assert_match(/https/, okta_credentials.errors[:url].join(" "))
    assert_match(/path/, okta_credentials.errors[:url].join(" "))
  end
end
