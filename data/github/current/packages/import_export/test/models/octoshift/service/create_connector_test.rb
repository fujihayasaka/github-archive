# typed: true
# frozen_string_literal: true

require "test_helper"

class OctoshiftServiceCreateConnectorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @org.add_member(@user, action: :admin)
    @name = Faker::App.name
    @url = Faker::Internet.url
    @connector_instance_type = "GITLAB"
  end

  test "returns connector id with a valid input" do
    actual_response = Octoshift::Service::CreateConnector.call(user: @user, owner: @org,
                                            name: @name,
                                            url: @url,
                                            connector_instance_type: @connector_instance_type)
    assert_kind_of String, actual_response
  end

  test "returns nil when user does not have permission to import" do
    user = create(:user)
    @org.add_member(user, action: :read)
    actual_response = Octoshift::Service::CreateConnector.call(user: user, owner: @org,
                                            name: @name,
                                            url: @url,
                                            connector_instance_type: @connector_instance_type)
    assert_nil actual_response
  end

  test "returns nil when twirp api call fails for whatever reason" do
    Octoshift::Service::CreateConnector.any_instance.stubs(:twirp_create_connector).returns({})
    actual_response = Octoshift::Service::CreateConnector.call(user: @user, owner: @org,
                                            name: @name,
                                            url: @url,
                                            connector_instance_type: @connector_instance_type)
    assert_nil actual_response
  end
end
