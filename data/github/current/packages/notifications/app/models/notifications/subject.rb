# typed: strict
# frozen_string_literal: true

module Notifications
  class Subject
    extend T::Sig

    sig { returns(String) }
    attr_reader :type

    sig { returns(Integer) }
    attr_reader :id

    sig { params(type: String, id: Integer).void }
    def initialize(type:, id:)
      @type = type
      @id = id
    end
  end
end
