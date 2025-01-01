# typed: true
# frozen_string_literal: true

require "github/throttler"
require "sorbet-runtime"
# Internal: Proxy class for `GitHub::Throttler` ensuring the correct throttler is (re-)used.
#
# The class also includes a module `DelegateMethods` that is included into every
# application record. Instead of using `GitHub::Throttler` directly, we use `.throttle`:
#
#     Repository.throttle do
#       Repository.create(...)
#     end
#
#     class Repository
#       def update_records
#         throttle { ... }
#       end
#     end
#
class ThrottlerBuilder
  attr_reader :throttler

  @instances = Hash.new do |hash, key|
    hash[key] = Instance.new(key)
  end

  def self.for(cluster_names)
    @instances[cluster_names]
  end

  class Instance
    include GitHub::Throttler::Base

    attr_reader :affected_clusters

    def initialize(affected_clusters)
      @affected_clusters = affected_clusters
    end
  end

  # Internal: A set of methods delegating throttling methods to the correct throttler instance.
  #
  # This module depends on a class and instance method called `cluster_name`.
  module DelegateMethods
    extend T::Helpers
    extend T::Sig
    abstract!

    sig { abstract.returns(T::Array[Symbol]) }
    def throttler_cluster_names; end

    def throttler
      ThrottlerBuilder.for(throttler_cluster_names)
    end

    def throttle(**arguments, &block)
      throttler.throttle(**arguments, &block)
    end

    def throttle_writes(**arguments, &block)
      ActiveRecord::Base.connected_to(role: :writing) do
        throttler.throttle(**arguments, &block)
      end
    end

    def throttle_with_retry(**arguments, &block)
      throttler.throttle_with_retry(**arguments, &block)
    end

    def throttle_writes_with_retry(**arguments, &block)
      ActiveRecord::Base.connected_to(role: :writing) do
        throttler.throttle_with_retry(**arguments, &block)
      end
    end
  end
end
