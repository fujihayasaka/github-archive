# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class Prelude < Platform::Loader
      def self.load(record, batch_method, *args)
        self.for(batch_method, args).load(record)
      end

      def initialize(batch_method, args)
        @batch_method = batch_method
        @args = args
      end

      def fetch(records)
        ::Prelude::Preloader.new(records).fetch(@batch_method, *@args)
        records.index_with { |record| record.public_send(@batch_method, *@args) }
      end
    end
  end
end
