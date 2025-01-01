# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class BlobWithPath < T::Struct
      const :oid, T.nilable(String)
      const :path, T.nilable(String)
      const :content, String

      # Overriding the equality method since tests fail due to comparing object IDs rather than values
      sig { params(other: SecretScanning::Models::BlobWithPath).returns(T::Boolean) }
      def ==(other)
        return false unless other.oid == self.oid
        return false unless other.path == self.path
        return false unless other.content == self.content
        true
      end
    end
  end
end
