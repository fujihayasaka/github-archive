# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class RepositoryActivities < ConnectionWrappers::Base
      extend T::Sig
      extend T::Helpers

      include Repos::ActivityViewDependency # All the business logic lives in this helper

      sig { override.returns(T.nilable(ActionDispatch::Request)) }
      def request
        nil
      end

      def initialize(**kwargs)
        super(nil, **kwargs)
        protect_against_duplicate_cursor_parameters!
        check_pagination_arguments!
      end

      def page_info
        self
      end

      def cursor_for(item)
        encode_cursor_v2(item.id, item.pushed_at)
      end

      def has_next_page
        async_load_data.then { @has_next_page }
      end

      def has_previous_page
        async_load_data.then { @has_previous_page }
      end

      def total_count
        async_load_data.then { @total_count ||= @pushes.count }
      end

      def start_cursor
        async_load_data.then { @start_cursor }
      end

      def end_cursor
        async_load_data.then { @end_cursor }
      end

      def edge_nodes
        async_load_data.then { @pushes }
      end

      private

      def cursor_version
        "v2"
      end

      def current_repository
        parent
      end

      def async_load_data
        return @load_promise if defined?(@load_promise)

        per_page = first || last
        sort = arguments[:order_by][:direction]

        time_period = arguments[:filter_by] && arguments[:filter_by][:time_period]
        activity_type = arguments[:filter_by] && arguments[:filter_by][:activity_type]
        actor_filter_present = arguments[:filter_by] && arguments[:filter_by][:actor]

        @load_promise = async_load_actor(arguments[:filter_by] && arguments[:filter_by][:actor]).then do |actor|
          @pushes, @has_previous_page, @has_next_page, @start_cursor, @end_cursor = fetch_pushes(
            per_page:,
            first:,
            last:,
            before:,
            after:,
            sort:,
            activity_type:,
            actor:,
            actor_filter_present:,
            time_period:,
            pushed_after: RELIABLE_PUSH_DATA_TIME
          )
        end
      end

      def async_load_actor(login)
        if login.present?
          Loaders::ActiveRecord.load(::User, login, column: :login, case_sensitive: false)
        else
          ::Promise.resolve(nil)
        end
      end

      # Current ref/branch name from the query params.
      def current_ref
        # If no ref parameter is present, we default to showing pushes for all branches
        return nil if arguments[:filter_by].blank?
        return nil if arguments[:filter_by][:ref].blank?

        if tree_name.present? && !tree_name.starts_with?("refs/")
          @current_ref = "refs/heads/#{tree_name}"
        else
          @current_ref = tree_name
        end
      end

      def tree_name
        return @tree_name if defined?(@tree_name)
        @tree_name ||= arguments[:filter_by].present? && arguments[:filter_by][:ref]
        @tree_name
      end

      def protect_against_duplicate_cursor_parameters!
        if before.present? && after.present?
          raise Errors::DuplicateBeforeAfterPaginationBoundaries.new(field)
        end
      end

      def check_pagination_arguments!
        if @first_value.nil? && @last_value.nil?
          raise Errors::MissingPaginationBoundaries.new(field)
        end
      end
    end
  end
end
