# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class Org < Base

        sig { returns(T::Array[Organization]) }; attr_reader :authorized_orgs

        sig { params(authorized_orgs: T::Array[Organization], kwargs: T.untyped).void }
        def initialize(authorized_orgs:, **kwargs)
          super(**T.unsafe(kwargs))
          @authorized_orgs = authorized_orgs
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if authorized_orgs.blank?

          orgs = without_selected_values
            .select { |o| o.display_login.include?(value) }
            .sort_by(&:display_login)
            .take(limit)

          orgs.map do |org|
            ::SecurityCenter::Suggestions::Suggestion.new(value: org.display_login)
          end
        end

        sig { returns(T::Array[Organization]) }
        memoize def without_selected_values
          selected_values_set = Set.new(selected_values)

          authorized_orgs.reject { |o| selected_values_set.include?(o.display_login) }
        end
      end
    end
  end
end
