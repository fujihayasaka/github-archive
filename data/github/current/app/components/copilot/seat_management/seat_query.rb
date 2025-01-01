# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class SeatQuery < T::Struct # rubocop:disable ViewComponent/ComponentsHaveUnitTests

      prop :query, String, default: ""
      prop :type, Symbol, default: :all
      prop :sort, Symbol, default: :nil_sort
      prop :direction, Symbol, default: :asc

      sig { params(params: ActionController::Parameters).returns(Copilot::SeatManagement::SeatQuery) }
      def self.generate(params)
        query = new
        if params[:query]
          query.query = params[:query]
        end

        if params[:type]
          query.type = params[:type].to_sym
        end

        if params[:sort]
          case params[:sort]
          when "name_asc"
            query.sort = :sortable_name
            query.direction = :asc
          when "name_desc"
            query.sort = :sortable_name
            query.direction = :desc
          when "use_asc"
            query.sort = :last_activity_at
            query.direction = :asc
          when "use_desc"
            query.sort = :last_activity_at
            query.direction = :desc
          when "requested_at_asc"
            query.sort = :requested_at
            query.direction = :asc
          when "requested_at_desc"
            query.sort = :requested_at
            query.direction = :desc
          when "pending_cancelled_asc"
            query.sort = :pending_cancellation_date
            query.direction = :asc
          when "pending_cancelled_desc"
            query.sort = :pending_cancellation_date
            query.direction = :desc
          end
        end

        query
      end
    end
  end
end
