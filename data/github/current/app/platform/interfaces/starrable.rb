# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module Starrable
      include Platform::Interfaces::Base
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
        scope_promise = case @object
        when Repository
          @context[:permission].async_can_list_stargazers?(object).then do |can_list_stargazers|
            if @context[:viewer]&.feature_enabled?(:restrict_graphql_emu_stargazer_lookup)
              user_ids = @object.stars.pluck(:user_id)
              users = User.where(id: user_ids)
              phantom_stargazer_promises = users.map do |user|
                @context[:permission].typed_can_see?("User", user).then { |p| p ? nil : user }
              end
              Promise.all(phantom_stargazer_promises).then do |phantom_stargazers|
                can_list_stargazers ? @object.stars.where.not(user_id: phantom_stargazers.compact.map(&:id)) : ::Star.none
              end
            else
              can_list_stargazers ? @object.stars : ::Star.none
            end
          end
        when Gist
          @context[:permission].async_can_list_gist_stargazers?(object).then do |can_list_gist_stargazers|
            can_list_gist_stargazers ? GistStar.where(gist_id: @object.id) : GistStar.none
          end
        when Topic
          Promise.resolve(@object.stars)
        end

        scope_promise.then do |scope|
          table = scope.table_name
          viewer = @context[:viewer]

          scope = if table == "starred_gists"
            filter_spam_for_gist_stargazers(scope, viewer)
          else
            scope.filter_spam_for(viewer)
          end

          if order_by = arguments[:order_by]
            # force a `user_hidden` ordering to select a better index
            scope = scope.order("#{table}.#{order_by[:field]} #{order_by[:direction]}")
          end

          if table == "stars"
            direction = order_by.present? ? order_by[:direction] : "ASC"
            scope = scope.order("#{table}.user_hidden #{direction}")
          end

          scope
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
