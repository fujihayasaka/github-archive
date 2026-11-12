# frozen_string_literal: true
module GraphQL
  module Pro
    class Dashboard
      class SubscriptionsComponent < Component
        def enabled?
          @schema.subscriptions.is_a?(GraphQL::Pro::Subscriptions)
        end

        template_path_from(__FILE__)

        configure_routes({
          "GET" => {
            "topics" => :topics_index,
            "topics/:topic" => :topics_show,
            "subscriptions/:subscription_id" => :subscriptions_show,
          },
          "POST" => {
            "subscriptions_clear" => :subscriptions_clear,
          }
        })

        def doc_url
          "http://graphql-ruby.org/subscriptions/pusher_implementation"
        end

        def topics_index(request:)
          page = (request.params["page"] || "1").to_i
          per_page = (request.params["per_page"] || "20").to_i
          offset = per_page * (page - 1)
          limit = per_page
          topics, all_topics_count, _has_next_page = @schema.subscriptions.topics(offset: offset, limit: limit)
          {
            tab: "subscriptions",
            title: "Subscription Topics",
            topics: topics,
            topics_count: all_topics_count,
            prev_page: page > 1 ? page - 1 : false ,
            next_page: all_topics_count > (offset + limit) ? page + 1 : false,
          }
        end

        def subscriptions_show(request:)
          subscription_id = request.params["subscription_id"]
          query_data = @schema.subscriptions.read_subscription(subscription_id)
          is_broadcast = @schema.subscriptions.broadcast_subscription_id?(subscription_id)

          if is_broadcast && @schema.subscriptions.show_broadcast_subscribers_count?
            subscribers_count = @schema.subscriptions.count_broadcast_subscribed(subscription_id)
            is_still_subscribed = subscribers_count > 0
          else
            subscribers_count = nil
            is_still_subscribed = @schema.subscriptions.still_subscribed?(subscription_id)
          end

          {
            tab: "subscriptions",
            title: "Subscription #{subscription_id}",
            subscription_id: subscription_id,
            query_data: query_data,
            still_subscribed: is_still_subscribed,
            is_broadcast: is_broadcast,
            subscribers_count: subscribers_count,
          }
        end

        def topics_show(request:)
          topic_name = request.params["topic"]
          all_subscription_ids = []
          @schema.subscriptions.each_subscription_id(topic_name) do |sid|
            all_subscription_ids << sid
          end

          page = (request.params["page"] || "1").to_i
          limit = (request.params["per_page"] || "20").to_i
          offset = limit * (page - 1)
          subscription_ids = all_subscription_ids[offset, limit]
          subs = @schema.subscriptions.read_subscriptions(subscription_ids)
          show_broadcast_subscribers_count = @schema.subscriptions.show_broadcast_subscribers_count?
          subs.each do |sub|
            sub[:is_broadcast] = is_broadcast = @schema.subscriptions.broadcast_subscription_id?(sub[:id])
            if is_broadcast && show_broadcast_subscribers_count
              sub[:subscribers_count] = sub_count = @schema.subscriptions.count_broadcast_subscribed(sub[:id])
              sub[:still_subscribed] = sub_count > 0
            else
              sub[:still_subscribed] = @schema.subscriptions.still_subscribed?(sub[:id])
              sub[:subscribers_count] = nil
            end
          end

          {
            tab: "subscriptions",
            title: "#{topic_name}",
            topic_name: topic_name,
            topic_last_triggered_at: @schema.subscriptions.topic_last_triggered_at(topic_name),
            subscriptions_count: all_subscription_ids.size,
            subscriptions: subs,
            next_page: all_subscription_ids.size > offset + limit ? page + 1 : false,
            prev_page: page > 1 ? page - 1 : false,
            show_broadcast_subscribers_count: show_broadcast_subscribers_count,
          }
        end

        def subscriptions_clear(request:)
          @schema.subscriptions.clear
          redirect_to("/topics")
        end
      end
    end
  end
end
