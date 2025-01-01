# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class RepositoryMigrations < ConnectionWrappers::Base
      def initialize(*args, **kwargs)
        super
        protect_against_duplicate_cursor_parameters!
      end

      def cursor_for(repository_migration)
        encode_cursor(repository_migration)
      end

      def page_info
        load_repository_migrations
        @page_info
      end

      def edge_nodes
        @edge_nodes ||= begin
          load_repository_migrations
          @repository_migrations.map do |migration|
            Platform::Objects::MigrationSource.load_from_global_id(
              migration.source_connector_id
            ).then do |migration_source|
              Octoshift::RepositoryMigration.new(migration, migration_source)
            end
          end
        end
      end

      def has_next_page
        if @has_next_page.nil?
          @has_next_page = load_reverse_pagination_check
        end
        @has_next_page
      end

      def has_previous_page
        if @has_previous_page.nil?
          @has_previous_page = load_reverse_pagination_check
        end
        @has_previous_page
      end

      def total_count
        @total_count ||= edge_nodes.count
      end

      private

      def build_page_info(repository_migrations:)
        PageInfo.new(
          start_cursor: encode_cursor(repository_migrations.first),
          end_cursor: encode_cursor(repository_migrations.last),
          connection: self,
        )
      end

      def protect_against_duplicate_cursor_parameters!
        # For the time being we won't support before and after cursors. Until
        # this gets added then, let's raise an exception.
        if before.present? && after.present?
          raise Errors::DuplicateBeforeAfterPaginationBoundaries.new
        end
      end

      def encode_cursor(migration)
        CursorGenerator.generate_cursor([migration.created_at.to_time.iso8601, migration.id], version: :v2) if migration
      end

      # Access Octoshift via twirp to load the organization repository migrations into `@repository_migrations`
      #
      # It also loads:
      #  - Forward-pagination check into `@has_next_page` or `@has_previous_page`
      #  - `@page_info`
      #
      # Returns nothing
      def load_repository_migrations
        return @repository_migrations if @repository_migrations

        # Depending on if first or last has been passed, set the offset.
        if before.present?
          @repository_migrations_cursor = before
          @repository_migrations_direction = :MIGRATION_ORDER_DIRECTION_DSC
        elsif after.present?
          @repository_migrations_cursor = after
          @repository_migrations_direction = :MIGRATION_ORDER_DIRECTION_ASC
        else
          @repository_migrations_cursor = nil
          if last.present?
            @repository_migrations_direction = :MIGRATION_ORDER_DIRECTION_DSC
          elsif first.present?
            @repository_migrations_direction = :MIGRATION_ORDER_DIRECTION_ASC
          end
        end

        edges_limit = (first || last)
        # Add 1 to the limit so we can see if there are any beyond this page
        repository_migrations_limit = edges_limit + 1

        repository_migrations = load_migrations(@items.id, @repository_migrations_cursor, @repository_migrations_direction, repository_migrations_limit)

        # Flip the results if backwards pagination search was made as octoshift returns them in reverse order
        if @repository_migrations_direction == :MIGRATION_ORDER_DIRECTION_DSC
          repository_migrations = repository_migrations.reverse
        end

        has_more_records = repository_migrations.length > edges_limit
        forward_pagination = first.present?
        backward_pagination = last.present?

        # Slice off the extra record we loaded in order to check for pagination
        if has_more_records
          if forward_pagination
            repository_migrations = repository_migrations.first(first)
          elsif backward_pagination
            repository_migrations = repository_migrations.last(last)
          end
        end

        if forward_pagination
          @has_previous_page = false if after.nil?
          @has_next_page = has_more_records
        elsif backward_pagination
          @has_previous_page = has_more_records
          @has_next_page = false if before.nil?
        end

        @page_info = build_page_info(repository_migrations: repository_migrations)

        sort_direction = arguments[:order_by][:direction]

        if sort_direction == :MIGRATION_ORDER_DIRECTION_ASC
          repository_migrations = repository_migrations.sort_by { |migration| migration.created_at.to_time }
        elsif sort_direction == :MIGRATION_ORDER_DIRECTION_DSC
          repository_migrations = repository_migrations.sort_by { |migration| migration.created_at.to_time }.reverse
        end

        @repository_migrations = repository_migrations
      end

      def load_migrations(owner_id, cursor, direction, limit)
        client_args = {
          owner_id: owner_id,
          limit: limit
        }

        client_args[:migration_state] = @arguments[:state] if @arguments[:state].present?
        client_args[:cursor] = cursor if cursor.present?
        client_args[:direction] = direction if direction.present?
        client_args[:repository_name] = Google::Protobuf::StringValue.new(value: @arguments[:repository_name]) if @arguments.key?(:repository_name)

        connection = Octoshift::Twirp::ConnectionBuilder.for_organization(@items).build
        migration_client = ::Octoshift::Twirp::MigrationClient.new(faraday_connection: connection)
        migration_client.get_migrations(**client_args)
      rescue Faraday::ConnectionFailed, Errno::ECONNRESET
        Octoshift::DatadogHelper.send_service_unavailable_stats(@items)
        raise(Errors::ServiceUnavailable, "GitHub Enterprise Importer is currently unavailable. Please try again later.")
      rescue Octoshift::Twirp::InvalidCursorError
        raise Errors::Cursor.new(cursor)
      end

      # Check if there are any items at all
      # in the _opposite_ direction
      def load_reverse_pagination_check
        load_repository_migrations
        cursor_direction = @repository_migrations_direction == :MIGRATION_ORDER_DIRECTION_DSC ? :MIGRATION_ORDER_DIRECTION_ASC : :MIGRATION_ORDER_DIRECTION_DSC
        reverse_repository_migrations = load_migrations(@items.id, @repository_migrations_cursor, cursor_direction, 1)
        reverse_repository_migrations.any?
      end
    end
  end
end
