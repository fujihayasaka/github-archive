# typed: true
# frozen_string_literal: true

class Actions::RepositoryUsage
  def self.usage_for(repository_id, time:)
    key = key(repository_id, time: time)
    kv(repository_id).get(key).value { 0 }.to_i
  end

  def self.set_usage_for(repository_id, time:, count:)
    key = key(repository_id, time: time)
    kv(repository_id).set(key, count.to_s, expires: 10.days.from_now.utc)
  end

  def self.increment_usage_for(repository_id, time:, count:)
    key = key(repository_id, time: time)
    kv(repository_id).increment(key, amount: count, expires: 10.days.from_now.utc)
    # The values returned by the increment method on a sharded cluster with a sequence table are currently wrong
    # Returning nil to protect aginast the value being used
    # https://github.com/github/github-kv/issues/27
    nil
  end

  def self.uses_in_the_past_week(repository_id)
    now = Time.now
    keys = (1..7).map do |lookback|
      time = (now - lookback.days)
      key(repository_id, time: time)
    end
    values = kv(repository_id).mget(keys).value { [] }
    values.sum(&:to_i)
  end

  class << self
    private

    def key(repository_id, time:)
      date = time.strftime "%Y-%m-%d"
      "actions:repo_usage:#{repository_id}:#{date}"
    end

    def kv(repository_id)
      Actions::KV.for_partition_key(repository_id)
    end
  end
end
