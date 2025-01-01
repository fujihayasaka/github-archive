# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    # Subtitle implements a very basic formatting for a common idiom in GitHub:
    #
    #   owner/repo #number
    #
    # Which generally refers to some content on a repository. It is extracted
    # and encapsulated here so that everybody using it keeps the same format.
    class Subtitle
      extend T::Sig

      sig { params(repository: T.nilable(::Repository), number: T.nilable(Numeric)).void }
      def initialize(repository:, number:)
        @repository = repository
        @number = number
      end

      sig { returns(String) }
      def to_s
        if number.nil?
          repository&.name_with_display_owner
        else
          "#{repository&.name_with_display_owner} ##{number}"
        end
      end

      private

      sig { returns(T.nilable(::Repository)) }
      attr_reader :repository
      sig { returns(T.nilable(Numeric)) }
      attr_reader :number
    end
  end
end
