# typed: true
# frozen_string_literal: true

module Trilogy::ActiveRecordInstantiationSubscriber
  def self.call(name, start, finish, id, payload = {})
    collector = GitHub::DataCollector::MysqlInstrumenterCollector.get_instance
    count = payload[:record_count]
    name = payload[:class_name]
    collector.active_record_obj_count += count
    collector.active_record_obj_types[name] += count
  end

  def self.subscribe
    return @subscriber if @subscriber

    @subscriber = ActiveSupport::Notifications.monotonic_subscribe(
      "instantiation.active_record",
      self,
    )
  end

  def self.unsubscribe
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    @subscriber = nil
  end
end
