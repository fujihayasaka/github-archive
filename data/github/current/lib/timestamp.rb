# typed: true
# frozen_string_literal: true

class Timestamp
  def self.from_time(time)
    time.to_i * 1000 + time.usec / 1000
  end

  def self.to_time(stamp)
    stamp ? Time.at(stamp.to_i / 1000, (stamp.to_i % 1000) * 1000) : Time.at(0)
  end

  # Public: Returns milliseconds since epoch.
  #
  # Returns an Integer.
  def self.milliseconds_since_epoch
    from_time(Time.now)
  end
end
