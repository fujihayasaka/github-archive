# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Starrable
      include Platform::Interfaces::Base
      include Scientist

      description "Things that can be starred."

      global_id_field :id, description: "The Node ID of the Starrable object"

      field :viewer_has_starred, Boolean, description: "Returns a boolean indicating whether the viewing user has starred this starrable.", null: false

      def viewer_has_starred
        viewer = @context[:viewer]
        if viewer.present? && @object.persisted?
          Loaders::HasStarredCheck.load(viewer.id, @object)
        else
          false
        end
      end

      field :viewer_can_star, Boolean,
        description: "Returns a boolean indicating whether the viewing user has the ability to star this starrable.",
        null: false, visibility: :under_development

      def viewer_can_star
        viewer = @context[:viewer]
        return false unless viewer.present? && @object.persisted?
        return true if @object.is_a?(Topic)

        viewer.async_can_star?(@object).then do |can_star|
          if !can_star
            false
          else
            true
          end
        end
      end

      field :stargazer_count, Integer, description: <<~DESCRIPTION, null: false do
          Returns a count of how many stargazers there are on this object
        DESCRIPTION
      end

      field :stargazers, Connections::Stargazer, description: "A list of users who have starred this starrable.", null: false, connection: true do
        argument :order_by, Inputs::StarOrder, "Order for connection", required: false
      end

      def stargazers(**arguments)
        pagination = GH::Pagination::Cursor.from_hash(@context[:current_arguments]&.to_h)
        direction = GH::Pagination::Sort::Direction.deserialize(arguments.dig(:order_by, :direction) || "ASC")
        field = arguments.dig(:order_by, :field) || "created_at"
        sorts = [GH::Pagination::Sort.new(field:, direction:)]
        id = T.must(@object.id)

        if @object.is_a?(Repositories::IRepository)
          @context[:permission].async_can_list_stargazers?(@object).then do |can_list_stargazers|
            next [] unless can_list_stargazers

            Stars.domain.repo_stars_not_spammy_for_viewer(id,
              viewer: @context[:viewer],
              pagination:,
              sorts:,
            )
          end
        elsif @object.is_a?(Topic)
          query = Stars.domain.topic_stars_not_spammy_for_viewer(id,
            viewer: @context[:viewer],
            pagination:,
            sorts:,
          )
          Promise.resolve(query)
        elsif @object.is_a?(Gist)
          query = Stars.domain.gist_stars_not_spammy_for_viewer(id,
            viewer: @context[:viewer],
            pagination:,
            sorts:,
          )
          Promise.resolve(query)
        else
          raise Platform::Errors::Internal, "Unexpected starrable type: #{@object.class}"
        end
      end

      def filter_spam_for_gist_stargazers(scope, viewer)
        return scope if !GitHub.spamminess_check_enabled? || viewer.try(:site_admin?)

        user_ids = scope.pluck(:user_id)
        non_spammy_user_ids = User.where(id: user_ids).filter_spam_for(viewer).pluck(:id)
        scope.where(user_id: non_spammy_user_ids)
      end
    end
  end
end
