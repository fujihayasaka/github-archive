# frozen_string_literal: true
require_relative "../dashboard_test"

class GraphQLProDashboardSubscriptionsComponentTest < GraphQLProDashboardTest
  class SubscriptionsTestSchema < GraphQL::Schema
    class CustomSubscriptions < GraphQL::Pro::PusherSubscriptions
      def read_subscription_failed_error(sub_id, query_data, err)
        delete_subscription(sub_id)
      end

      attr_accessor :show_broadcast_subscribers_count

      BROADCAST_CHANNEL_TAG = "Dummy-"
    end

    REDIS = Redis.new(db: REDIS_NUMBERS[:dashboard])
    PUSHER = MockPusher.new

    class Query < GraphQL::Schema::Object
      field :int, Integer, null: false
    end

    class ClockTicked < GraphQL::Schema::Subscription
      field :value, Integer, null: false
    end

    class Subscription < GraphQL::Schema::Object
      field :clock_ticked, subscription: ClockTicked, broadcastable: false
      field :clock_ticked_broadcast, subscription: ClockTicked
    end

    query(Query)
    subscription(Subscription)
    use CustomSubscriptions, pusher: PUSHER, redis: REDIS, broadcast: true, default_broadcastable: true
  end

  def setup
    @schema = SubscriptionsTestSchema
    SubscriptionsTestSchema::REDIS.flushdb
  end

  def exec(*args, **kwargs)
    @schema.execute(*args, **kwargs)
  end

  # See the Integration tests in test/sinatra
  def test_it_renders_disabled
    @schema = OperationStoreHelpers::ActiveRecordBackendSchema
    get "/topics"
    assert_equal 200, last_response.status
    assert_body_includes "SubscriptionsComponent"
    assert_body_includes "is not configured"
    assert_body_includes "http://graphql-ruby.org/subscriptions/pusher_implementation"
  end

  def test_it_renders_new_and_old_subscriptions
    get "/topics"
    assert_equal 200, last_response.status
    refute_body_includes "is not configured"

    query_opts = {}
    query_str = "subscription { clockTicked { value } }"

    res1, res2, res3, res4, created_at = nil

    Timecop.freeze do
      created_at = Time.now
      @schema.subscriptions.new_subscriptions = false
      res1 = exec(query_str, **query_opts)
      res2 = exec(query_str, **query_opts)

      get "/topics"
      assert_body_includes '<td><a href="/topics/%3AclockTicked%3A" >:clockTicked:</a></td>'
      assert_body_includes '<td>2</td>'

      @schema.subscriptions.new_subscriptions = true
      res3 = exec(query_str, **query_opts)
      res4 = exec(query_str, **query_opts)
    end

    online_sub_id = res4.context[:subscription_id]
    SubscriptionsTestSchema::PUSHER.channel(online_sub_id).occupant_entered
    assert @schema.subscriptions.still_subscribed?(online_sub_id)

    created_at_s = created_at.strftime("%FT%T%:z")
    created_at_el = "<time datetime=\"#{created_at_s}\" class=\"localize-date\">#{created_at_s}</time>"
    created_at_td = "<td>#{created_at_el}</td>"

    get "/topics"
    assert_body_includes '<td><a href="/topics/%3AclockTicked%3A" >:clockTicked:</a></td>'
    assert_body_includes '<td>4</td>'
    assert_body_includes '<td>—</td>', "Last triggered at"

    get "/topics/:clockTicked:"
    assert_body_includes "4 Subscriptions"
    assert_body_includes '<td><code>NO</code></td>'
    assert_body_includes '<td><code>YES</code></td>'
    [res1, res2, res3, res4].each_with_index do |res, idx|
      assert res.context[:subscription_id], "Res #{idx} has an ID"
      assert_body_includes res.context[:subscription_id]
      assert_body_includes created_at_td
    end

    [res1, res2, res3, res4].each_with_index do |res, idx|
      sub_id = res.context[:subscription_id]
      get "/subscriptions/#{sub_id}"
      assert_body_includes sub_id
      assert_body_includes query_str
      assert_body_includes "Created at #{created_at_el}, last triggered at —"
      if sub_id == online_sub_id
        assert_body_includes "<p>Subscribed? <code>YES</code></p>"
      else
        assert_body_includes "<p>Subscribed? <code>NO</code></p>"
      end
    end

    res5 = exec(query_str, context: { bogus: { "__gid__" => "gid://bogus" } })
    get "/subscriptions/#{res5.context[:subscription_id]}"
    assert_body_includes res5.context[:subscription_id]
    assert_body_includes "This subscription was not found or is no longer active."

    triggered_at = Time.new(2025, 1, 1)
    SubscriptionsTestSchema::REDIS.set("gql:sub:topics::clockTicked::tr", triggered_at.to_i)
    get "/topics"
    triggered_at_s = triggered_at.strftime("%FT%T%:z")
    triggered_at_el = "<time datetime=\"#{triggered_at_s}\" class=\"localize-date\">#{triggered_at_s}</time>"
    triggered_at_td = "<td>#{triggered_at_el}</td>"
    assert_body_includes triggered_at_td, "Last triggered at"
  end

  def test_it_shows_subscriber_count_when_configured_to_do_so
    assert_equal false, @schema.subscriptions.show_broadcast_subscribers_count?

    query_opts = {}
    query_str = "subscription { clockTickedBroadcast { value } }"

    res1, res2 = nil

    Timecop.freeze do
      res1 = exec(query_str, **query_opts)
      res2 = exec(query_str, **query_opts)
    end


    online_sub_id = res1.context[:subscription_id]
    channel = SubscriptionsTestSchema::PUSHER.channel(online_sub_id)
    channel.occupant_entered
    channel.occupant_entered

    broadcast_dunno_str = "This subscription may have multiple subscribers"
    online_count_str = "(2 subscribers)"
    sub_count_header = "<th>Subscribers</th>"
    get "/topics/:clockTickedBroadcast:"
    refute_body_includes sub_count_header
    get "/subscriptions/#{online_sub_id}"
    refute_body_includes online_count_str
    assert_body_includes broadcast_dunno_str

    @schema.subscriptions.show_broadcast_subscribers_count = true

    get "/topics/:clockTickedBroadcast:"
    assert_body_includes sub_count_header
    get "/subscriptions/#{online_sub_id}"
    assert_body_includes online_count_str
    refute_body_includes broadcast_dunno_str
  ensure
    @schema.subscriptions.show_broadcast_subscribers_count = false
  end
end
