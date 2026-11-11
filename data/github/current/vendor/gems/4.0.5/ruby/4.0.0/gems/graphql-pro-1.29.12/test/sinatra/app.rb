# frozen_string_literal: true

require "graphql"
require "graphql-pro"
require "sinatra"
require "thin"
require "globalid"
require "redis"
require "pusher"
require "ably-rest"
require_relative "app/counter"
require_relative "app/schema"

Pusher.app_id = "418263"
Pusher.key = "b504d3788bb4b14c156b"
Pusher.secret = "ae269444c976412db74f"
Pusher.cluster = 'us2'
Pusher.encrypted = true

# Clear the subscriptions database
App::Schema.subscriptions.clear

GlobalID.app = "test-app"

get "/" do
  erb :pusher
end

get "/ably" do
  erb :ably
end

# Send queries here, it will provide a Channel ID which the client _may_ open
post "/graphql" do
  content_type "application/json"
  context = {
    ably_channel_id: "x", # IRL, a function of the viewer
  }

  res = App::Schema.execute(params[:query], variables: params[:variables], context: context)
  response_headers = {}
  sub_id = res.context[:subscription_id]
  if sub_id
    response_headers["x-subscription-id"] = sub_id
  end
  [200, response_headers, JSON.dump(res)]
end
