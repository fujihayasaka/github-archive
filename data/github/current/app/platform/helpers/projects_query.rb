# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class ProjectsQuery
      attr_reader :model_to_be_queried

      def initialize(owner, args, user)
        @args = args
        @owner = owner

        case owner
        when ::Repository
          @project_type = "repo"
        when ::Organization
          @project_type = "org"
        when ::User
          @project_type = "user"
        end

        @model_to_be_queried = ::Project
        @user = user
      end

      def query_hash
        hash = {
          current_user: @user,
          repo_id: owner_id_for("repo"),
          org_id: owner_id_for("org"),
          user_id: owner_id_for("user"),
          project_type: @project_type,
          phrase: "#{@args[:search]} in:name",
        }

        hash[:state] = state_filter if state_filter
        hash[:public] = true unless @args[:include_private]

        hash
      end

      def order_by_field
        return unless order_by_values.present?
        order_by_values[:field]
      end

      def order_by_field_valid?
        Platform::Enums::ProjectOrderField.values.map { |_, v| v.value }.include?(order_by_field)
      end

      def order_by_direction
        return unless order_by_values.present?
        order_by_values[:direction]
      end

      def order_by_direction_valid?
        Platform::Enums::OrderDirection.values.map { |_, v| v.value }.include?(order_by_direction)
      end

      # There are two potential ways to get state, one from the explicit
      # "states" argument that can be passed through GraphQL and the other is
      # having an "is:open" or "is:closed" in the search string. Precedence is
      # given to the "states" argument.
      #
      # Returns "open", "closed" or nil
      def state_filter
        @state_filter ||= begin
          state = nil

          filter = @args[:states] ||
            parsed_search_query.select { |(k, _v)| k == :is }.map { |(_k, v)| v }

          if filter.present? && filter.length == 1
            filter_value = filter.pop
            if Platform::Enums::ProjectState.values.map { |_, v| v.value }.include?(filter_value)
              state = filter_value
            end
          end
          state
        end
      end

      # If the search string contains something other than "is:<state>" or
      # "sort:<field-direction>" it is the string that will be used to match the
      # name field.
      #
      # Returns a the name search string if present
      def name_filter
        parsed_search_query.find { |component| component.is_a?(String) }
      end

      def parsed_search_query
        @parsed_search_query ||= Search::Queries::ProjectQuery.normalize(
          Search::Queries::ProjectQuery.parse(@args[:search]),
        )
      end

      def query
        @query ||= ::Search::Queries::ProjectQuery.new(query_hash)
      end

      # Using a separarate query for count lookups, adding aggregation
      # to the query causes problems with pagination because there is an
      # error when trying to use `count` for getting the total count.
      def counts_query
        agg_hash = query_hash.merge(aggregations: :state)
        @counts_query ||= ::Search::Queries::ProjectQuery.new(agg_hash)
      end

      private

      # There are two potential ways to get sort order, one from the explicit
      # "orderBy" argument that can be passed through GraphQL and the other is
      # having a "sort:created-asc" or similar in the search string. Precedence is
      # given to the "orderBy" argument.
      #
      # Returns a hash with the field and direction, nil if none exist

      def order_by_values
        @order_by_values ||= begin
          values = {}

          if @args[:order_by]
            values[:field] = @args[:order_by][:field]
            values[:direction] = @args[:order_by][:direction]
          else
            sort_value = parsed_search_query.find { |(k, _v)| k == :sort }
            if sort_value.present?
              field, direction = sort_value.pop.split("-")
              case field
              when "created"
                values[:field] = "created_at"
              when "updated"
                values[:field] = "updated_at"
              when "name"
                values[:field] = "name"
              end

              if direction == "desc"
                values[:direction] = "DESC"
              else
                values[:direction] = "ASC"
              end
            end
          end
          values
        end
      end

      def owner_id_for(owner_type)
        return @owner.id if owner_type == @project_type
        nil
      end
    end
  end
end
