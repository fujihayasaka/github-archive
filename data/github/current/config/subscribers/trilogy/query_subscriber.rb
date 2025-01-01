# typed: true
# frozen_string_literal: true

require "connection_info"

module Trilogy::QuerySubscriber
  def self.call(name, start, finish, id, payload = {})
    if payload[:cached]
      GitHub::MysqlInstrumenter.track_cached_query(payload)
    else
      GitHub::MysqlInstrumenter.track_query(start, finish, payload)
    end
  end

  def self.subscribe
    return @subscriber if @subscriber

    @subscriber = ActiveSupport::Notifications.monotonic_subscribe(
      "sql.active_record",
      self,
    )
  end

  def self.unsubscribe
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    @subscriber = nil
  end
end

if !GitHub::AppEnvironment.test?
  Trilogy::QuerySubscriber.subscribe
end
