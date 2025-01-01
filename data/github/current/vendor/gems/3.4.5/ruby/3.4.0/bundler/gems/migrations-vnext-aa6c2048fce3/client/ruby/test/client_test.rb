# frozen_string_literal: true

require "test_helper"

class MvndClientTest < Minitest::Test
  def setup
    @host = "http://localhost:3000"
    @hmac_key = "test_hmac_key"
    @client = Mvnd::Client.new(@host, hmac_key: @hmac_key)
  end

  def test_create_resource
    repo = Mvnd::Migrations::Api::V1::Repository.new(
      resource_id: "http://github.com/github/github", 
      is_private: true, 
      user_id: 1
    )
    resource = Mvnd::Migrations::Api::V1::Resource.new(
      repository: repo, 
      location: :RESOURCE_LOCATION_TYPE_INLINE
    )
    request = Mvnd::Migrations::Api::V1::CreateResourceRequest.new(
      resource: resource
    )
    
    mock_twirp_client = Minitest::Mock.new
    mock_twirp_client.expect :create_resource, nil, [request]

    @client.stub :twirp_client, mock_twirp_client do
      @client.create_resource(resource)
    end

    mock_twirp_client.verify
  end
end
