# typed: strict
# frozen_string_literal: true

module Billing
  module Interfaces
    module RemoteFileStorage
      extend T::Helpers

      interface!

      sig { abstract.params(file_name: String, file: String, options: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def upload(file_name:, file:, options:); end

      sig { abstract.params(file_name: String).returns(String) }
      def download(file_name:); end

      sig { abstract.params(file_name: String, expires_in: ActiveSupport::Duration).returns(String) }
      def get_url(file_name:, expires_in:); end

      sig { abstract.params(file_name: String).returns(T::Boolean) }
      def delete(file_name:); end
    end
  end
end
