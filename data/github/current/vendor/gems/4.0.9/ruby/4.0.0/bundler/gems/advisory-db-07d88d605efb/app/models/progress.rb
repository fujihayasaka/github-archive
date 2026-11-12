# frozen_string_literal: true

class Progress
  attr_reader :id, :totals, :counts

  def initialize(id, total: 100, count: 0, totals: { default: total }, counts: { default: count })
    @id = id
    @totals = totals
    @counts = counts
  end

  def subscribe(timeout: 1.minute)
    redis.subscribe_with_timeout(timeout, channel) do |on|
      on.message do |_channel, message|
        data = YAML.safe_load(message, permitted_classes: [Symbol])
        event, totals, counts = data.fetch_values(:event, :totals, :counts)

        self.totals.replace(totals)
        self.counts.replace(counts)

        yield event
      end
    end
  rescue Redis::TimeoutError
    yield :timeout
  end

  def unsubscribe
    redis.unsubscribe(channel)
  end

  def increment(key = :default, by: 1)
    counts[key] ||= 0
    counts[key] += by

    publish(:increment)
    publish(:finish) if finished?
  end

  def total(key = nil)
    key ? totals.fetch(key, 0) : totals.values.sum
  end

  def count(key = nil)
    key ? counts.fetch(key, 0) : counts.values.sum
  end

  def percentage(key = nil, precision: 0)
    percent = total(key) == 0 ? BigDecimal(100) : (count(key).to_d / total(key) * 100)
    percent.round(precision, BigDecimal::ROUND_DOWN)
  end

  def finished?(key = nil)
    count(key) >= total(key)
  end

  private

  def redis
    AdvisoryDB.redis
  end

  def channel
    "progress:#{id}"
  end

  def publish(event)
    data = { event: event, totals: totals, counts: counts }
    message = YAML.dump(data)
    redis.publish(channel, message)
  end
end
