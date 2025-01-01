# typed: true
# frozen_string_literal: true

module Apps::Transfers
  class TargetAutocompleteComponent < ApplicationComponent

    sig { params(suggestions: T::Array[T.any(User, Organization, Business)]).void }
    def initialize(suggestions:)
      @suggestions = suggestions
    end

    private

    sig { returns(T::Array[T.any(User, Organization, Business)]) }
    attr_reader :suggestions

    def suggestion_type(suggestion)
      if suggestion.is_a?(Organization)
        "organization"
      elsif suggestion.is_a?(User)
        "user"
      else
        "enterprise"
      end
    end

    def suggestion_value(suggestion)
      "#{suggestion.display_login}/#{suggestion.id}"
    end

    def params_transfer_to(suggestion)
      "#{suggestion.class.name}/#{suggestion.id}"
    end
  end
end
