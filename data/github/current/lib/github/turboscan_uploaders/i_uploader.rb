# typed: strict
# frozen_string_literal: true

module GitHub
  module TurboscanUploaders
    module IUploader
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(sarif: String, target: String).returns(String) }
      def upload(sarif, target); end

      sig { abstract.returns(String) }
      def class; end

    end
  end
end
