# typed: true
# frozen_string_literal: true

module GraphQLExtensions
  module ScopesForBuiltIns
    def minimum_accepted_scopes
      nil
    end

    def scopeless_tokens_as_minimum?
      true
    end
  end
end
