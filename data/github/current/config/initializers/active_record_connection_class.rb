# typed: true
# frozen_string_literal: true

require "active_record/connection_adapters/abstract/connection_pool"
require "active_record/connection_adapters/abstract_adapter"
require "active_record/connection_adapters/pool_config"

ActiveRecord::ConnectionAdapters::AbstractAdapter.class_eval do
  delegate :connection_class, to: :pool
end

ActiveRecord::ConnectionAdapters::ConnectionPool.class_eval do
  delegate :connection_class, to: :pool_config
end

ActiveRecord::ConnectionAdapters::PoolConfig.class_eval do
  if defined?(Rails.application) && Rails.application.config.cache_classes
    def connection_class
      @connection_class ||= connection_name.constantize
    end
  else
    def connection_class
      connection_name.constantize
    end
  end

  # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
  def connection_name
    T.bind(self, ActiveRecord::ConnectionAdapters::PoolConfig)
    connection_descriptor.instance_variable_get(:@name)
  end
  # rubocop:enable GitHub/AvoidDynamicInstanceVariableMethods
end
