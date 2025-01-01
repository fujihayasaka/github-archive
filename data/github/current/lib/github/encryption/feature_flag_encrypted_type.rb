# typed: true
# frozen_string_literal: true

module GitHub
  module Encryption
    class FeatureFlagEncryptedType < ::ActiveRecord::Type::Text
      attr_accessor :scheme, :cast_type, :attribute_name, :model_name, :table_name

      delegate :deserialize, :changed_in_place?, to: :cast_type
      delegate :with_context, to: :scheme

      def initialize(scheme:, cast_type:, attribute_name:, model_name:, table_name:)
        raise RuntimeError, "Not an EncryptedAttributeType" unless cast_type.is_a?(ActiveRecord::Encryption::EncryptedAttributeType)

        @scheme = scheme
        @cast_type = cast_type
        @attribute_name = attribute_name
        @model_name = model_name
        @table_name = table_name
      end

      def serialize(value)
        if GitHub.enterprise? || GitHub.flipper["encrypt_as_plaintext_#{model_name.underscore.gsub("/", "_")}_#{attribute_name.downcase}"].enabled?
          GitHub.dogstats.increment("encrypted_column.encryption_skipped", tags: ["table:#{@table_name}", "attribute:#{@attribute_name}"])
          return nil if value.nil?
          cast_type.cast_type.serialize(value)
        else
          GitHub.dogstats.increment("encrypted_column.encryption_performed", tags: ["table:#{@table_name}", "attribute:#{@attribute_name}"])
          cast_type.serialize(value)
        end
      end

      def encrypted?(value)
        with_context { encryptor.encrypted? value }
      end

      private

      def encryptor
        ActiveRecord::Encryption.encryptor
      end
    end
  end
end
