# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class ActorTenant
    sig { returns(String) }
    attr_reader :name

    sig { returns(T.nilable(Integer)) }
    attr_reader :id

    sig { params(name: String, id: T.nilable(Integer)).void }
    def initialize(name, id)
      @id = T.let(id, T.nilable(Integer))
      @name = T.let(name, String)
    end
  end
end
