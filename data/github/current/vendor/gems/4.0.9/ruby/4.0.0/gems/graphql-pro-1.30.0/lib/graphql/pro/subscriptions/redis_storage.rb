# frozen_string_literal: true
require "graphql/pro/redis_script_client"
require "ostruct"

module GraphQL
  module Pro
    class Subscriptions < GraphQL::Subscriptions
      # @api private
      class RedisStorage
        PREFIX = "gql:sub:"
        # Limit the number of keys passed to Lua to avoid "too many results to unpack"
        BATCH_SIZE = 5000
        class ScriptClient < GraphQL::Pro::RedisScriptClient
          register :filter_active_subscriptions, <<-LUA
            local topic_key = KEYS[1]
            local subscription_keys = {unpack(KEYS, 2)}
            local all_subscription_ids = ARGV
            local active_subscription_ids = {}
            local inactive_subscription_ids = {}
            local inactive_subscription_keys = {}
            local subscription_id = nil
            local subscription_values = redis.call('mget', unpack(subscription_keys))

            for i, subscription_value in ipairs(subscription_values) do
              subscription_id = all_subscription_ids[i]
              if subscription_value == false or subscription_value == '' then
                inactive_subscription_keys[#inactive_subscription_keys + 1] = subscription_keys[i]
                inactive_subscription_ids[#inactive_subscription_ids + 1] = subscription_id
              else
                active_subscription_ids[#active_subscription_ids + 1] = subscription_id
              end
            end

            if #inactive_subscription_keys ~= 0 then
              redis.call('del', unpack(inactive_subscription_keys))
              redis.call('srem', topic_key, unpack(inactive_subscription_ids))
            end

            if #active_subscription_ids == 0 then
              redis.call('del', topic_key)
            end

            return active_subscription_ids
          LUA

          register :subscription_ids_for_fingerprint_keys, <<-LUA
            -- This will hold arrays of results, mapping to the keys in sequence
            local results = {}
            local all_subscription_ids = nil
            for _i, fingerprint_subscriptions_key in ipairs(KEYS) do
              all_subscription_ids = redis.call('smembers', fingerprint_subscriptions_key)
              results[#results + 1] = all_subscription_ids
            end
            return results
          LUA

          register :clean_inactive_subs, <<-LUA
            -- return an array for each set of fingerprint subscription IDs
            local results = {}
            local fingerprint_subscriptions_keys_size = tonumber(ARGV[1])
            local fingerprint_subscriptions_keys = {unpack(KEYS, 1, fingerprint_subscriptions_keys_size)}
            local all_subscription_keys = {unpack(KEYS, 1 + fingerprint_subscriptions_keys_size)}
            local subscription_keys_lengths = {unpack(ARGV, 2)}
            local keys_offset = 0
            local keys_length = nil
            local subscriptions = nil
            local subscription_keys = nil
            local subscription_key = nil
            -- a `1` indicates that the corresponding ID is active
            local active_subscription_indicators = nil

            for i, fingerprint_subscriptions_key in ipairs(fingerprint_subscriptions_keys) do
              keys_length = tonumber(subscription_keys_lengths[i])
              active_subscription_indicators = {}
              if keys_length > 0 then
                subscription_keys = {unpack(all_subscription_keys, keys_offset + 1, keys_offset + keys_length)}
                subscriptions = redis.call('mget', unpack(subscription_keys))
                for j, subscription_value in ipairs(subscriptions) do
                  subscription_key = subscription_keys[j]
                  if subscription_value == false or subscription_value == '' then
                    -- this is garbage
                    redis.call('del', subscription_key)
                    redis.call('srem', fingerprint_subscriptions_key, subscription_key)
                    active_subscription_indicators[#active_subscription_indicators + 1] = 0
                  else
                    active_subscription_indicators[#active_subscription_indicators + 1] = 1
                  end
                end
              end

              results[#results + 1] = active_subscription_indicators
              keys_offset = keys_offset + keys_length
            end

            return results
          LUA

          register :delete_subscription, <<-LUA
            local all_topics_key = KEYS[1]
            local subscription_key = KEYS[2]
            local subscription_id = ARGV[1]
            local topics_size = tonumber(ARGV[2])
            local topic_key = nil
            local topic_subscribers_remaining = nil
            local fingerprint_subscribers_remaining = nil
            local remaining = nil
            local fingerprint_subscriptions_key = nil
            local topic_fingerprints_key = nil
            local topic_tr_key = nil
            local fingerprint = nil
            local topic = nil

            local end_of_topic_keys = 2 + (topics_size * 3)

            for topic_idx = 1, topics_size, 1 do
              local topic_offset = topic_idx * 3
              topic_key = KEYS[topic_offset]
              redis.call('srem', topic_key, subscription_id)

              topic_subscribers_remaining = redis.call('scard', topic_key)
              if topic_subscribers_remaining == 0 then
                redis.call('del', topic_key)
              end

              topic_fingerprints_key = KEYS[1 + topic_offset]
              topic_tr_key = KEYS[2 + topic_offset]

              fingerprint_subscriptions_key = KEYS[end_of_topic_keys + topic_idx]
              fingerprint_subscribers_remaining = nil
              if fingerprint_subscriptions_key then
                redis.call('srem', fingerprint_subscriptions_key, subscription_id)
                remaining = redis.call('scard', fingerprint_subscriptions_key)
                if remaining == 0 then
                  redis.call('del', fingerprint_subscriptions_key)
                  fingerprint = ARGV[3 + topics_size + topic_idx]
                  redis.call('srem', topic_fingerprints_key, fingerprint)
                  fingerprint_subscribers_remaining = redis.call('scard', topic_fingerprints_key)
                  if fingerprint_subscribers_remaining == 0 then
                    redis.call('del', topic_fingerprints_key)
                  end
                end
              end

              if fingerprint_subscribers_remaining == nil then
                fingerprint_subscribers_remaining = redis.call('scard', topic_fingerprints_key)
              end

              if (topic_subscribers_remaining == 0 and fingerprint_subscribers_remaining == 0) then
                topic = ARGV[3 + topic_idx]
                redis.call('srem', all_topics_key, topic)
                redis.call('del', topic_tr_key)
              end
            end
            redis.call('del', subscription_key)
          LUA
        end

        def initialize(redis: nil, connection_pool: nil, subscriptions:, stale_ttl:)
          @script_client = ScriptClient.new(redis, connection_pool: connection_pool)
          @stale_ttl = stale_ttl
          # This reference is used for loading & dumping context
          @subscriptions = subscriptions
        end

        # Record a few things:
        # - Query data for this subscription
        # - Add this subscription to each topic's list of subscriptions
        # - Add these topics to the global list of topics
        def write_subscription(query, events)
          sub_id = query.context[:subscription_id] || raise("Failed to get subscription id")
          query_string = query.query_string ? query.query_string : query.document.to_query_string
          query_hash = {
            query_string: query_string,
            variables: query.provided_variables.to_json,
            context_string: @subscriptions.dump_context(query.context),
            operation_name: query.operation_name,
            topics: events.map(&:topic),
            created_at: Time.now.to_i,
            last_triggered_at: nil,
          }
          if @subscriptions.new_subscriptions
            fingerprints = events.map(&:fingerprint)
            query_hash[:fingerprints] = fingerprints
          end
          query_data = JSON.dump(query_hash)
          sub_key = subscription_key(sub_id)

          if @subscriptions.new_subscriptions
            with_redis do |redis|
              redis.multi do |m|
                # Setting a TTL here means that the whole system has to be ready
                # to receive `nil` from this key.
                # (This _should_ be handled well already --
                # see `#delete_subscription`, `#each_subscription_id`)
                m.set(sub_key, query_data, ex: @stale_ttl)
                m.sadd(all_topics_key, events.map(&:topic))
                events.each do |event|
                  t = event.topic
                  f = event.fingerprint
                  m.sadd(fingerprints_key(t), [f])
                  m.sadd(fingerprint_subscriptions_key(f), [sub_id])
                end
              end
            end
          else
            with_redis do |redis|
              redis.multi do |m|
                m.set(sub_key, query_data, ex: @stale_ttl)
                events.each do |event|
                  m.sadd(all_topics_key, [event.topic])
                  t_key = topic_key(event.topic)
                  m.sadd(t_key, [sub_id])
                end
              end
            end
          end

          nil
        end

        # This subscription received an update, reset the TTL
        # (No-op when no TTL is configured)
        # @param subscription_id [String, Array<String>]
        # @return void
        def reset_ttl(subscription_id)
          if @stale_ttl
            if subscription_id.is_a?(Array)
              keys = subscription_id.map { |sid| subscription_key(sid) }
              with_redis do |redis|
                redis.multi do |m|
                  keys.each { |k| m.expire(k, @stale_ttl) }
                end
              end
            else
              key = subscription_key(subscription_id)
              with_redis { |redis| redis.expire(key, @stale_ttl) }
            end
          end
          nil
        end

        # Fetch the query data for this subscription
        def read_subscription(sub_id)
          read_subscriptions([sub_id]).first
        end

        def read_subscriptions(sub_ids)
          if sub_ids.empty?
            return []
          end
          sub_keys = sub_ids.map { |sid| subscription_key(sid) }
          query_data_strs = with_redis { |r| r.mget(sub_keys) }
          query_data_strs.each_with_index.map do |query_data_str, idx|
            # It's possible that the subscription was cleaned up _between_
            # the call to `each_subscription_id` and this call.
            # Or, it could have expired due to TTL.
            # In that case, return nil, and handle this upstream to skip this subscription.
            if query_data_str.nil? || query_data_str.size == 0
              nil
            else
              begin
                sub_id = sub_ids[idx]
                query_data = JSON.parse(query_data_str)
                context_str = query_data.fetch("context_string")
                context = @subscriptions.load_context(context_str)
                variables_h = JSON.parse(query_data.fetch("variables"))
                {
                  id: sub_id,
                  query_string: query_data.fetch("query_string"),
                  variables: variables_h,
                  context: context,
                  operation_name: query_data.fetch("operation_name"),
                  created_at: query_data["created_at"] && Time.at(query_data["created_at"].to_i), # This is missing for old subscriptions
                  last_triggered_at: query_data["last_triggered_at"] && Time.at(query_data["last_triggered_at"].to_i), # This is missing for old subscriptions
                  topics: query_data["topics"],
                  fingerprints: query_data["fingerprints"] || [],
                }
              rescue StandardError => err
                @subscriptions.read_subscription_failed_error(sub_id, query_data, err)
                nil
              end
            end
          end
        end

        def each_subscription_id_legacy(topic)
          t_key = topic_key(topic)
          all_subscription_ids = with_redis { |redis| redis.smembers(t_key) }
          if all_subscription_ids.any?
            all_subscription_keys = all_subscription_ids.map { |sid| subscription_key(sid) }
            keys = [t_key, *all_subscription_keys]
            values = all_subscription_ids
            active_subscription_ids = @script_client.exec_script(:filter_active_subscriptions, keys, values)
            active_subscription_ids.each { |sid| yield(sid) }
          end
          nil
        end

        def each_fingerprint_and_subscription_ids(topic, touch_last_triggered_at: false, &block)
          fingerprints_key = fingerprints_key(topic)
          # This was broken down from a big Lua script because
          # we have to convert values in to keys, and Redis (and libraries like redis-namespace)
          # really require keys to come in via the `keys` array.
          all_fingerprints = with_redis { |r|
            if touch_last_triggered_at
              t_last_triggered_at_key = topic_last_triggered_at_key(topic)
              r.set(t_last_triggered_at_key, Time.now.to_i)
            end
            r.smembers(fingerprints_key)
          }
          all_fingerprints.each_slice(BATCH_SIZE) do |fingerprints|
            fingerprint_subscription_keys = fingerprints.map { |f| fingerprint_subscriptions_key(f) }
            all_subscription_ids_for_fingerprint_keys = @script_client.exec_script(:subscription_ids_for_fingerprint_keys, fingerprint_subscription_keys, [])

            batch_fingerprints = []
            batch_fs_keys = []
            batch_sub_keys = []
            batch_sub_ids_for_fingerprint = []
            current_batch_size = 0
            all_subscription_ids_for_fingerprint_keys.each_with_index do |sub_ids, sk_idx|
              if sub_ids.any?
                i = 0
                batch_fs_keys << fingerprint_subscription_keys[sk_idx]
                batch_fingerprints << fingerprints[sk_idx]
                these_sub_ids = []
                batch_sub_ids_for_fingerprint << these_sub_ids
                these_sub_keys = []
                batch_sub_keys << these_sub_keys
                while sub_ids.any?
                  if (i += 1) > 10_000
                    raise "Invariant: Iterated 10,000 times preparing keys for Lua"
                  end
                  remaining_size = BATCH_SIZE - current_batch_size
                  ids_slice = sub_ids.pop(remaining_size)
                  keys_slice = ids_slice.map { |id| subscription_key(id) }
                  these_sub_keys.concat(keys_slice)
                  these_sub_ids.concat(ids_slice)
                  # May be less than `remaining_size`
                  current_batch_size += ids_slice.size
                  if current_batch_size >= BATCH_SIZE
                    run_fingerprint_batch(fingerprints_key, batch_fingerprints, batch_sub_ids_for_fingerprint, batch_fs_keys, batch_sub_keys, &block)
                    current_batch_size = 0
                    if sub_ids.any?
                      # prepare a new batch picking up where this one left off
                      batch_fs_keys << fingerprint_subscription_keys[sk_idx]
                      batch_fingerprints << fingerprints[sk_idx]
                      these_sub_ids = []
                      batch_sub_ids_for_fingerprint << these_sub_ids
                      these_sub_keys = []
                      batch_sub_keys << these_sub_keys
                    end
                  end
                end
              end
            end

            if batch_fs_keys.any?
              run_fingerprint_batch(fingerprints_key, batch_fingerprints, batch_sub_ids_for_fingerprint, batch_fs_keys, batch_sub_keys, &block)
            end
          end
          nil
        end

        def touch_last_triggered_at(subscription_ids)
          if subscription_ids.any?
            sub_keys = subscription_ids.map { |id| subscription_key(id) }
            sub_data_strs = with_redis { |r| r.mget(sub_keys) }
            redis_info = {}

            sub_data_strs.each_with_index do |data_str, data_idx|
              if data_str.nil? || data_str == ""
                # skip it, it's not there
              else
                data_h = JSON.parse(data_str)
                data_h["last_triggered_at"] = Time.now.to_i
                new_data_str = JSON.dump(data_h)
                redis_info[sub_keys[data_idx]] = new_data_str
              end
            end

            if redis_info.any?
              with_redis do |r|
                r.pipelined do |pipeline|
                  redis_info.each do |sub_key, sub_str|
                    pipeline.set(sub_key, sub_str, keepttl: true)
                  end
                end
              end
            end
          end
        end

        # Find each subscription for the triggered topic
        def each_subscription_id(topic)
          any_subscriptions = false

          each_subscription_id_legacy(topic) do |sub_id|
            any_subscriptions = true
            yield(sub_id)
          end

          each_fingerprint_and_subscription_ids(topic) do |f, f_sub_ids|
            f_sub_ids.each do |f_sub_id|
              any_subscriptions = true
              yield(f_sub_id)
            end
          end

          # Any subscriptions that used to exist for this topic
          # have been TTL'ed, deleted, GC'ed, etc --
          # remove this topic from the list of all topics.
          if !any_subscriptions
            remove_topic(topic)
          end
          nil
        end

        def remove_topic(topic)
          with_redis { |r|
            r.srem(all_topics_key, [topic])
            r.del(topic_last_triggered_at_key(topic))
          }
        end

        # Delete this subscription by:
        # - removing it from each of its topics lists of subscriptions
        # - if it was the last subscriber to a topic, removing the topic from the list of topics
        # - removing its query data
        # @param query_data [Hash] The result of `read_subscription`, if it's already available.
        def delete_subscription(sub_id, subscription: nil)
          sub_key = subscription_key(sub_id)
          if subscription
            topics = subscription[:topics]
            fingerprints = subscription[:fingerprints]
          else
            query_data_str = with_redis { |r| r.get(sub_key) }
            if query_data_str.nil? || query_data_str == ""
              return
            else
              query_data = JSON.parse(query_data_str)
              topics = query_data["topics"]
              # This can be `nil` for legacy subscription data:
              fingerprints = query_data["fingerprints"] || []
            end
          end

          # _Part_ of this could be implemented with `multi` --
          # but not the part that checks list size and cleans up where needed.
          # If this operation in particular proved to be to CPU-intensive on Redis,
          # it could be split into two parts:
          # - A `multi` operation to run deletes and srems;
          # - A script for checking list sizes and cleaning up where necessary.
          # But that would have the downside of making two round trips.
          keys = [all_topics_key, sub_key]
          topics.each { |t|
            keys << topic_key(t)
            keys << fingerprints_key(t)
            keys << topic_last_triggered_at_key(t)
          }
          fingerprints.each { |f|
            keys << fingerprint_subscriptions_key(f)
          }
          argv = [sub_id, topics.size, fingerprints.size, *topics, *fingerprints]
          @script_client.exec_script(:delete_subscription, keys, argv)
        end

        # Clear all subscription state
        def clear(cursor: nil)
          while cursor != "0"
            cursor ||= "0" # This is the initial value
            cursor, keys = with_redis { |r| r.scan(cursor, match: "#{PREFIX}*", count: 100) }
            if keys.any?
              with_redis { |r| r.del(*keys) }
            end
          end
        end

        # For the UI:
        def topics(limit:, offset:)
          all_topic_names = with_redis { |r| r.smembers(all_topics_key) }
          topic_names = if limit.nil? && offset.nil?
            all_topic_names
          else
            all_topic_names[offset, limit] || []
          end

          topics = topic_names.map do |t|
            topic_sub_count = nil
            topic_last_triggered_at = nil
            with_redis { |r|
              legacy_topic_sub_count = r.scard(topic_key(t))
              new_topic_sub_count = r.scard(fingerprints_key(t))
              topic_sub_count = legacy_topic_sub_count + new_topic_sub_count
              topic_last_triggered_at = r.get(topic_last_triggered_at_key(t))
            }
            OpenStruct.new(
              name: t,
              last_triggered_at: topic_last_triggered_at ? Time.at(topic_last_triggered_at.to_i) : nil ,
              subscriptions_count: topic_sub_count,
            )
          end
          return topics, all_topic_names.size
        end

        # For the ui:
        def topic_last_triggered_at(topic)
          key = topic_last_triggered_at_key(topic)
          v = with_redis { |r| r.get(key) }
          v ? Time.at(v.to_i) : nil
        end

        private

        # This key holds query data for `sub_id`
        def subscription_key(sub_id)
          "#{PREFIX}query:#{sub_id}"
        end

        # This key holds subscription ids for `topic`
        def topic_key(topic)
          "#{PREFIX}topics:#{topic}"
        end

        def topic_last_triggered_at_key(topic)
          "#{PREFIX}topics:#{topic}:tr"
        end

        def all_topics_key
          "#{PREFIX}alltopics"
        end

        def fingerprints_key(topic)
          "#{PREFIX}fingerprints:#{topic}"
        end

        def fingerprint_subscriptions_key(fingerprint)
          "#{PREFIX}fingerprintsubscriptions:#{fingerprint}"
        end

        def with_redis(&block)
          @script_client.with_redis(&block)
        end

        # @return void
        def run_fingerprint_batch(fingerprints_key, fingerprints, batch_sub_ids_for_fingerprint, fs_keys, sub_keys_for_fs_keys)
          keys = fs_keys + sub_keys_for_fs_keys.flatten

          args = [
            fs_keys.size,
            *sub_keys_for_fs_keys.map { |s_keys| s_keys.size },
          ]

          filtered_subscription_keys = @script_client.exec_script(:clean_inactive_subs, keys, args)
          active_size = 0
          cleanup_fingerprints = []
          fingerprints.each_with_index do |fingerprint, idx|
            active_subscription_ids = []
            all_subscription_ids = batch_sub_ids_for_fingerprint[idx]
            # Inspect the result. If a `1` is present, then the corresponding ID is active.
            filtered_subscription_keys[idx].each_with_index do |presence_indicator, sub_idx|
              if presence_indicator == 1
                active_subscription_ids << all_subscription_ids[sub_idx]
              end
            end

            if active_subscription_ids.empty?
              cleanup_fingerprints << fingerprint
            else
              active_size += 1
              yield(fingerprint, active_subscription_ids)
            end
          end

          if cleanup_fingerprints.any?
            cleanup_fingerprint_keys = cleanup_fingerprints.map { |f| fingerprint_subscriptions_key(f) }
            with_redis do |r|
              r.multi do |m|
                m.srem(fingerprints_key, cleanup_fingerprints)
                m.del(cleanup_fingerprint_keys)
              end
            end
          end

          fs_keys.clear
          sub_keys_for_fs_keys.clear
          fingerprints.clear
          batch_sub_ids_for_fingerprint.clear
          nil
        end
      end
    end
  end
end
