# typed: true
# frozen_string_literal: true

# The ToggledServiceCollection keeps track of which services have been acted on
# whenever the ServiceManager is enabling or disabling services.
#
# We use this information in order to perform post-processing (e.g. instrumentation)
# at the end of toggling multiple services.
module SecurityProduct
  class ToggledServiceCollection
    delegate :empty?, :[], :[]=, to: :collection

    def self.create(service_symbol, options)
      new.add(service_symbol, options)
    end

    def self.empty
      new
    end

    def initialize
      @collection = {}
    end

    def add(service_symbol, options = {})
      self[service_symbol] = options
      self
    end

    def merge!(other)
      collection.merge!(other.collection)
      self
    end

    def services
      @collection.keys
    end

    protected

    attr_reader :collection
  end
end
