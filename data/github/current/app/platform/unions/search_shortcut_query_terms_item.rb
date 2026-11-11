# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class SearchShortcutQueryTermsItem < Platform::Unions::Base
      description "A search shortcut query term entry."

      possible_types(
        Objects::SearchShortcutQueryCategoryTerm,
        Objects::SearchShortcutQueryLabelTerm,
        Objects::SearchShortcutQueryLoginRefTerm,
        Objects::SearchShortcutQueryMilestoneTerm,
        Objects::SearchShortcutQueryProjectTerm,
        Objects::SearchShortcutQueryRepoTerm,
        Objects::SearchShortcutQueryTerm,
        Objects::SearchShortcutQueryText,
      )

      def self.resolve_type(object, context)
        return nil unless object.is_a?(Hash) && object.key?(:term)

        return Objects::SearchShortcutQueryText unless object[:matched]

        case object[:name]
        when *::SearchQueryable::LOGIN_REF_QUERY_TERMS
          Objects::SearchShortcutQueryLoginRefTerm
        when :repo
          Objects::SearchShortcutQueryRepoTerm
        when :label
          Objects::SearchShortcutQueryLabelTerm
        when :milestone
          Objects::SearchShortcutQueryMilestoneTerm
        when :category
          Objects::SearchShortcutQueryCategoryTerm
        when :project
          Objects::SearchShortcutQueryProjectTerm
        else
          Objects::SearchShortcutQueryTerm
        end
      end
    end
  end
end
