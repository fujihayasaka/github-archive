# typed: true
# frozen_string_literal: true

module Notifyd
  class UnsubscribeResourceTypeFactory
    class StandardResource
      attr_reader :klass

      def initialize(klass:)
        @klass = klass
      end

      def fetch(id: nil)
        klass.find_by(id: id)
      end
    end

    class TransferableResource
      attr_reader :klass, :transfer_klass

      def initialize(klass:)
        @klass = klass
        @transfer_klass = "#{klass}Transfer".constantize
      end

      def fetch(id:)
        result = klass.find_by(id: id)
        return result if result.present?
        find_transfered_resource(id: id)
      end

      def find_transfered_resource(id:)
        new_id = transfer_klass.find_new_id_by_original_id(original_id: id)
        return nil if new_id.nil?
        klass.find_by(id: new_id)
      end
    end

    def self.build(klass:)
      if klass == Issue || klass == Discussion
        TransferableResource.new(klass: klass)
      else
        StandardResource.new(klass: klass)
      end
    end
  end
end
