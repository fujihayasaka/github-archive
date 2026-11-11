# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class FromAddress
      Layout = Notifyd::Proto::Layouts::Email


      sig { params(author: Author).void }
      def initialize(author:)
        @author = author
      end

      sig { returns(T.nilable(Notifyd::Proto::Layouts::Email::From)) }
      def serialize
        name = author.profile_name

        name.present? ? Layout::From.new(name: name) : nil
      end

      private

      sig { returns(Author) }
      attr_reader :author
    end
  end
end
