# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class RepositoryActivities < Resolvers::Base
      include Repos::ActivityViewDependency
      # Needed to include the Repos::ActivityViewDependency module.
      sig { override.returns(T.nilable(ActionDispatch::Request)) }
      def request
        nil
      end

      type Connections.define(Objects::Activity), null: false

      argument :order_by, Inputs::ActivityOrder, "Ordering options for activities returned from the connection.", required: false, default_value: { field: "timestamp", direction: "DESC" }
      argument :filter_by, Inputs::ActivityFilters, "Filtering options for activities returned from the connection.", required: false

      def resolve(**arguments)
        ref = arguments.dig(:filter_by, :ref)
        ref = "refs/heads/#{ref}" if ref.present? && !ref.start_with?("refs/")

        Loaders::ActiveRecord.load(::User, arguments.dig(:filter_by, :actor), column: :login, case_sensitive: false).then do |actor|
          fetch_pushes_from_domain(
            repository_id: object.id,
            ref:,
            first: context[:current_arguments][:first],
            last: context[:current_arguments][:last],
            before: context[:current_arguments][:before],
            after: context[:current_arguments][:after],
            sort: arguments[:order_by][:direction],
            activity_type: arguments[:filter_by] && arguments[:filter_by][:activity_type],
            actor:,
            actor_filter_present: arguments.dig(:filter_by, :actor).present?,
            time_period: arguments[:filter_by] && arguments[:filter_by][:time_period],
            pushed_after: RELIABLE_PUSH_DATA_TIME
          )
        end
      end
    end
  end
end
