# typed: true
# frozen_string_literal: true

module Biztools
  module RepositoryActions
    class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include GitHub::Memoizer
      include OcticonsHelper

      attr_reader :action

      delegate :name, :security_email, :slug, :description, :color,
        :path, :rank_multiplier, :icon_name, :icon_color, to: :action, prefix: true

      def initialize(action:, current_user: nil, user_session: nil)
        @action = action
        @current_user = current_user
      end

      def owner_verified?
        action.verified_owner?
      end

      def elasticsearch_entry
        query = Search::Queries::MarketplaceQuery.new(current_user: @current_user, type: "repository-action", phrase: action.name)
        result = query.execute.results.detect { |r| r["_id"].to_i == action_id }
        return "No entry found" if result.nil?
        result
      end

      def icon(checked)
        checked ? octicon("check-circle", color: :success) : octicon("x-circle", color: :danger)
      end

      def repository_public_icon
        icon(!action.repository.private?)
      end

      def repository_has_action_icon
        icon(action.repository.action_at_root.present?)
      end

      def metadata_icon
        icon(action.config_from_metadata_file.any?)
      end

      # agreement_icon returns the agreement signature status. If the action is owned by an org,
      # we check for a signature, if the action is owned by a user, we default to false because we
      # can't be sure who is publishing the action.
      def agreement_icon
        has_signed = if owned_by_org?
          action.org_has_signed_integrator_agreement?(org: action.owner)
        else
          false
        end

        icon(has_signed)
      end

      def owned_by_org?
        action.owned_by_org?
      end

      def action_id
        action.id
      end

      def action_featured?
        action.featured
      end

      def action_listed?
        action.listed?
      end

      def action_repository_url
        urls.repository_path(action.repository)
      end

      def action_owner_login
        action.repository.owner_login
      end

      memoize def repository_action_releases_count
        action.repository_action_releases.count
      end
    end
  end
end
