# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class RepositoryRecommendationComponent < RepoBaseComponent
      REASON_ICONS = {
        "followed" => :flame,
        "topics" => :telescope,
      }.freeze

      REASON_LINK_ATTRIBUTES = {
        "trending" => {
          href_attributes: { helper: :trending_index_path },
          click_target: "trending",
          text: "GitHub",
        },
        "topics" => {
          href_attributes: {
            helper: :users_stars_topics_path,
            params: { user: "%{current_user}", filter: :topics },
            required: [:current_user],
          },
          click_target: "topics",
          text: "your topics",
        },
        "followed" => {
          href_attributes: {
            helper: :user_path,
            args: ["%{current_user}?tab=following"],
            required: [:current_user],
          },
          click_target: "following",
          text: "people you follow",
        },
      }.freeze

      private

      delegate :reason, to: :item

      def repo_has_details?
        repository.stargazer_count > 0 ||
        repository.primary_language_name.present?
      end

      def include_star_button?
        repository.owner.present?
      end

      def repo_recommendation_icon
        REASON_ICONS.fetch(reason, :star)
      end

      def link_to_repo_recommendation
        attributes = REASON_LINK_ATTRIBUTES[reason]
        return unless attributes

        href_attributes = attributes[:href_attributes]
        checks = Array(href_attributes[:required]).map { |attr| public_send(attr).present? }

        if checks.all?
          render(
            Primer::Beta::Link.new(
              href: build_href(href_attributes),
              scheme: :primary,
              underline: false,
              data: helpers.feed_clicks_hydro_attrs(
                click_target: attributes[:click_target],
                feed_item: item,
              ),
            ),
          ) { attributes[:text] }
        end
      end

      def build_href(href_attributes)
        substitutions = { current_user: current_user&.display_login }.compact
        params = href_attributes[:params] || {}
        params = params.transform_values { |v| v.is_a?(String) ? v % substitutions : v }
        params = params.presence || href_attributes[:args]&.map { |arg| arg % substitutions }

        public_send(href_attributes[:helper], params)
      end
    end
  end
end
