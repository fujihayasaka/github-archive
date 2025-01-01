# typed: strict
# frozen_string_literal: true

# The ToggledServiceCollection keeps track of which services have been acted on
# whenever the ServiceManager is enabling or disabling services.
#
# We use this information in order to perform post-processing (e.g. instrumentation)
# at the end of toggling multiple services.
module SecurityProduct
  class ToggledServiceCollection
    delegate :empty?, :[], :[]=, to: :collection

    sig { params(service_symbol: Symbol, options: T.untyped).returns(ToggledServiceCollection) }
    def self.create(service_symbol, options)
      new.add(service_symbol, options)
    end

    sig { returns(ToggledServiceCollection) }
    def self.empty
      new
    end

    sig { void }
    def initialize
      @collection = T.let({}, T::Hash[Symbol, T.untyped])
    end

    sig { params(service_symbol: Symbol, options: T.untyped).returns(ToggledServiceCollection) }
    def add(service_symbol, options = {})
      self[service_symbol] = options
      self
    end

    sig { params(other: ToggledServiceCollection).returns(ToggledServiceCollection) }
    def merge!(other)
      collection.merge!(other.collection)
      self
    end

    sig { returns(T::Array[Symbol]) }
    def services
      @collection.keys
    end

    protected

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :collection
  end
end
