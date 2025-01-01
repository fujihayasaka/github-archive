# typed: true
# frozen_string_literal: true

module Stratocaster
  class MemoryStore
    def initialize
      reset!
    end

    def save(event)
      if event.id
        set event.id, event
      else
        create event
      end
    end

    def create(event)
      event.id = @num += 1
      set event.id, event
    end

    def get(id)
      if hash = @client[id.to_s]
        Event.new hash
      end
    end

    def set(id, event)
      event.updated_at = Time.now.utc
      event.created_at ||= event.updated_at
      @client[id.to_s] = stringify_payload(event.to_hash)
      @last = id
      event
    end

    def delete(id)
      @client.delete id.to_s
    end

    def all
      @client.values.map { |v| Event.new(v) }
    end

    def last
      get @last
    end

    def get_all(*keys)
      keys.map { |k| get(k) }
    end

    def delete_all(*keys)
      keys.map { |k| delete(k) }
    end

    def reset!
      @num = 0
      @client = {}
    end

    private

    PAYLOAD_KEYS = [:payload, "payload"]

    def stringify_payload(event_hash)
      key = PAYLOAD_KEYS.detect { |k| event_hash.key?(k) }
      return event_hash unless key
      deep_stringify_hash(event_hash[key])
      event_hash
    end

    def deep_stringify_hash(hash)
      hash.keys.each do |k|
        hash[k.to_s] = stringify_value(hash.delete(k))
      end
      hash
    end

    def deep_stringify_array(array)
      array.map! { |v| stringify_value(v) }
    end

    def stringify_value(value)
      case value
      when Hash then deep_stringify_hash(value)
      when Array then deep_stringify_array(value)
      else value
      end
    end
  end
end
