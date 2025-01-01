# typed: true
# frozen_string_literal: true

module Stafftools
  module Search
    class AuditLogAdvancedSearchView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      def advanced_search_fields
        ::Search::Queries::StafftoolsQuery::SEARCHABLE_FIELDS
      end

      def advanced_search_label_pretify(key)
        key.to_s.gsub("data.", "").humanize.gsub(".", " ")
      end
    end
  end
end
