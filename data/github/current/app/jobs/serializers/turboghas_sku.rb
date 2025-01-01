# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Serializers
  class TurboghasSKU < ActiveJob::Serializers::ObjectSerializer
    sig { params(sku: GitHub::Turboghas::SKU).returns(Hash) }
    def serialize(sku)
      super("value" => sku.to_param)
    end

    sig { params(hash: Hash).returns(GitHub::Turboghas::SKU) }
    def deserialize(hash)
      klass.from_param(hash["value"])
    end

    private

    sig { returns(T.class_of(GitHub::Turboghas::SKU)) }
    def klass
      GitHub::Turboghas::SKU
    end
  end
end
