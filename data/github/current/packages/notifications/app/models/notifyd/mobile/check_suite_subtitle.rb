# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class CheckSuiteSubtitle
      extend T::Sig

      sig { params(repository: ::Repository).void }
      def initialize(repository:)
        @repository = repository
      end

      sig { returns(String) }
      def to_s
        "#{@repository.name_with_display_owner}"
      end
    end
  end
end
