# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class NotificationListFilter < ::Search::Filter
      LIST_TYPE_MAPPING = {
        repo: Repository,
        team: Team,
      }

      def initialize(opts = {})
        super(opts)
        @current_user = options.fetch(:current_user)
      end

      def must
        filters = LIST_TYPE_MAPPING.keys.map { |key| build_list_filter(key, qualifiers[key].must) }.compact
        build_should_filter(filters)
      end

      def must_not
        filters = LIST_TYPE_MAPPING.keys.map { |key| build_list_filter(key, qualifiers[key].must_not) }.compact
        build_should_filter(filters)
      end

      private

      def build_should_filter(filters)
        return if filters.empty?

        {
          bool: { should: filters },
        }
      end

      def build_list_filter(qualifier_key, qualifier_values)
        list_type = Newsies::List.type_from_class(LIST_TYPE_MAPPING[qualifier_key])
        list_ids = active_record_ids_from_qualifier(qualifier_key, qualifier_values)

        return unless list_ids.present?

        {
          bool: {
            must: [
              build_term_filter(:list_type, list_type),
              build_term_filter(:list_id, list_ids),
            ],
          },
        }
      end

      def active_record_ids_from_qualifier(qualifier_key, values)
        ids = Array(values).map do |value|
          case qualifier_key
          when :repo
            repo = Repository.nwo(value)
            next unless repo&.readable_by?(@current_user)
            repo.id
          when :team
            team = Team.find_by_combined_slug(value.gsub(/\A@/, ""))
            next unless team&.visible_to?(@current_user)
            team.id
          end
        end
        ids.compact!
        ids
      end
    end
  end
end
