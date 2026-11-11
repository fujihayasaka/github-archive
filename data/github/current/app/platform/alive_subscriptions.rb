# typed: strict
# frozen_string_literal: true

module Platform
  class AliveSubscriptions < GraphQL::Subscriptions
    class ClientError < RuntimeError; end

    # Implemented by graphql gem, wrapped for metrics
    sig { params(event_name: Symbol, args: T::Hash[Symbol, T.untyped], object: T.untyped, scope: T.nilable(String)).void }
    def trigger(event_name, args, object: {}, scope: nil)
      GitHub.dogstats.distribution_time("graphql_subscriptions.trigger.time", tags: ["subscription_event:#{event_name}"]) do
        super(event_name, args, object, scope: scope)
      end
    rescue ClientError, Faraday::ConnectionFailed, Faraday::TimeoutError, Subscription::MissingData, Platform::Errors::UnknownQuery => e
      Failbot.report(e)
    end

    sig { params(event: GraphQL::Subscriptions::Event, object: T.untyped).void }
    def execute_all(event, object)
      each_subscription_id(event) do |subscription_id|
        execute(subscription_id, event, object)
      end
    end

    # Yields a hash containing subscription meta data
    # for the graphql gem to use to deliver updates
    # we are not delivering update but rather the meta data which is required for the shim from the client to fetch the update
    sig { params(event: GraphQL::Subscriptions::Event, block: T.proc.params(arg0: T.untyped).void).void }
    def each_subscription_id(event, &block)
      channel_name = Subscription.current_format.generate_channel_name(topic: event.topic, subscription_arguments: event.arguments)

      current_subscription = {
        arguments: event.arguments,
        channel_name: channel_name,
        event_name: event.name
      }
      yield(current_subscription)
    end

    # Called by the graphql gem as part of subscription lifecycle
    #
    # subscription - the yielded hash from each_subscription_id
    # event - GraphQL::Subscriptions::Event
    # object - The object loaded when the event is triggered
    sig { params(subscription: T.untyped, event: GraphQL::Subscriptions::Event, object: T.untyped).returns(T.untyped) }
    def execute_update(subscription, event, object)
      subscription_topic = event.topic

      # <scope>:<event>:argName:argValue:argName:argValue
      # ":issueCommentDeleted:comment:IC_kwAPzPc:id:I_kwAPFw"
      parts = subscription_topic.split(Subscription::DELIMITER)
      scope = if parts.length > 1 && parts[0].length > 0
        parts[0]
      else
        nil
      end
      context = {
        scope_object: object,
        subscription_topic: subscription_topic,
        scope: scope,
      }
      context
    end

    # Run the update query for this subscription and deliver it
    # @see {#execute_update}
    # @see {#deliver}
    # @return [void]
    sig { params(subscription_id: T.untyped, event: T.untyped, object: T.untyped).void }
    def execute(subscription_id, event, object)
      res = execute_update(subscription_id, event, object)
      if !res.nil?
        deliver(subscription_id, res)
      end
    end

    # Called by graphql gem's execute method
    # to send the payload to the proper subscribers
    #
    # subscription - the yielded hash from each_subscription_id
    # result - the result of executing the subscription
    sig { params(subscription: T.untyped, result: T.untyped).void }
    def deliver(subscription, result)
      result[:dispatch_time] = Time.now.utc.to_f
      GitHub::WebSocket.notify_graphql_subscription_channel(subscription[:channel_name], result.to_h)
    end

    # Required by graphql gem
    #
    # Just the identity function because the decoded subscription id
    # *is* the subscription.
    sig { params(subscription: T.untyped).returns(T.untyped) }
    def read_subscription(subscription)
      subscription
    end

    # Required by graphql gem
    #
    # We do not have the ability to delete subscriptions, a user is subscribed
    # as long as they are connected to alive.
    sig { params(subscription: T.untyped).void }
    def delete_subscription(subscription)
    end

    # Called by graphql gem
    #
    # Writes the subscription id to the context as part of the initial
    # subscription execution so it can be used by the Relay store
    sig { params(query: T.untyped, events: T.untyped).void }
    def write_subscription(query, events)
      if events.size != 1
        # TODO: we should make it possible to subscribe to multiple events in a single
        # operation, but for now we only support one event per subscription.
        raise Platform::Errors::Internal, "expecting exactly one event, got #{events.size}"
      end

      user, user_session = require_context!(query, :viewer, :user_session)
      if !user.instance_of?(User)
        raise Platform::Errors::Internal, "Only Users may create subscriptions, got #{user.class.name} (id #{user.id})"
      end

      event = events.first
      topic = event.topic
      subscription_arguments = event.arguments

      channel_name = Subscription.current_format.generate_channel_name(
        topic:,
        subscription_arguments:
      )
      # Stash this here so it can be set as a header in the response, which
      # will connect to Alive
      query.context[:subscription_id] = GitHub::WebSocket.signed_channel(channel_name)
    end

    sig { params(query: T.untyped, keys: Symbol).returns(T::Array[T.untyped]) }
    def require_context!(query, *keys)
      context = query.context
      keys.map do |key|
        context.fetch(key) do
          raise Platform::Errors::Internal, "required key #{key.inspect} not present in context"
        end
      end
    end
  end
end
