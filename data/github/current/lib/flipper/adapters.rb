# typed: true
# frozen_string_literal: true

module Flipper
  module Adapters
    autoload :Dual, "flipper/adapters/dual"
    autoload :EnabledByDefault, "flipper/adapters/enabled_by_default"
    autoload :InMemory, "flipper/adapters/in_memory"
    autoload :InstrumentedWithLazy, "flipper/adapters/instrumented_with_lazy"
    autoload :LazyActors, "flipper/adapters/lazy_actors"
    autoload :Memcacheable, "flipper/adapters/memcacheable"
    autoload :Mysql, "flipper/adapters/mysql"
    autoload :Override, "flipper/adapters/override"
  end
end
