# typed: true
# frozen_string_literal: true

require "dalli"

module GitHub
  module Cache
    module Compatibility

      def get(key, raw = false)
        result = super(key, raw)
        return result if raw || result.nil?
        GitHub::Cache::Codec.unpack(result)
      end

      def get_multi(keys, raw = false)
        result = super(keys, raw)
        result.transform_keys! { |k| k.delete_prefix(GitHub.cache.namespace) }
        result.transform_values! { |v|  GitHub::Cache::Codec.unpack(v) if v } unless raw
      end
    end
  end
end
