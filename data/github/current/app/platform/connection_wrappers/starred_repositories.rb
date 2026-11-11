# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class StarredRepositories < ConnectionWrappers::Base
      class OrderedByIdCursor
        def self.decode(opaque)
          values = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(opaque)
          return nil unless values.is_a?(Array) &&
            values.size >= 1 &&
            values[0].is_a?(Integer)

          new(values[0])
        end

        def initialize(star_id)
          @star_id = star_id
        end

        attr_reader :star_id

        include Comparable

        def <=>(other)
          @star_id <=> other.star_id
        end

        def encode
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([@star_id], version: :v2)
        end
      end

      class OrderedByDateTimeCursor < OrderedByIdCursor
        def self.decode(opaque)
          values = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(opaque)
          return nil unless values.is_a?(Array) &&
            values.size >= 2 &&
            values[0].is_a?(String) &&
            values[1].is_a?(Integer)

          new(DateTime.iso8601(values[0]), values[1])
        rescue Date::Error
          nil
        end

        def initialize(datetime, star_id)
          super star_id

          @datetime = datetime
        end

        attr_reader :datetime

        def <=>(other)
          result = @datetime <=> other.datetime

          if result.nil?
            @datetime.nil? ? -1 : 1
          elsif result.zero?
            super other
          else
            result
          end
        end

        def encode
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([@datetime&.iso8601, @star_id], version: :v2)
        end
      end

      class OrderedByWatcherCountCursor < OrderedByIdCursor
        def self.decode(opaque)
          values = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(opaque)
          return nil unless values.is_a?(Array) &&
            values.size >= 1 &&
            values[0].is_a?(Integer) &&
            values[1].is_a?(Integer)

          new(values[0], values[1])
        end

        def initialize(watcher_count, star_id)
          super star_id

          @watcher_count = watcher_count
        end

        attr_reader :watcher_count

        def <=>(other)
          result = @watcher_count <=> other.watcher_count
          return result unless result.to_i.zero?

          super other
        end

        def encode
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([@watcher_count, @star_id], version: :v2)
        end
      end

      LIMIT = 50000
      BATCH_SIZE = 10000

      # type - choose from "public", "private", "source", "fork", "mirror", "sponsorable";
      #        see Enums::StarredRepositoryType
      def initialize(items, field:, owned_by_viewer:, order_by:, repository_database_ids:, type:, **args)
        super items, max_page_size: Schema::DEFAULT_MAX_PER_PAGE, **args

        @order_by = order_by || { field: "id", direction: "ASC" }
        @owned_by_viewer = owned_by_viewer
        @repository_database_ids = repository_database_ids
        @type = type

        @loaded = false
      end

      def over_limit?
        @items.stars.repositories.count > LIMIT
      end

      def nodes
        @nodes ||= if cursors_for_current_page.any?
          Platform::Loaders::ActiveRecord.load_all(::Star, cursors_for_current_page.map(&:star_id))
        else
          ::Promise.resolve([])
        end
      end

      def has_next_page
        load_data

        @has_next_page
      end
      alias :has_next_page? :has_next_page

      def has_previous_page
        load_data

        @has_previous_page
      end
      alias :has_previous_page? :has_previous_page

      def start_cursor
        cursors_for_current_page.first&.encode
      end

      def end_cursor
        cursors_for_current_page.last&.encode
      end

      def cursor_for(node)
        case @order_by[:field]
        when "pushed_at"
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.starrable.pushed_at&.iso8601, node.id],
            version: :v2)
        when "watcher_count"
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.starrable.stargazer_count, node.id],
            version: :v2)
        when "created_at"
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.created_at&.iso8601, node.id],
            version: :v2)
        else
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.id], version: :v2)
        end
      end

      def total_count
        cursors_for_given_order.size
      end

      private

      def cursors_for_given_order
        @cursors ||= case @order_by[:field]
        when "pushed_at"
          cursors_for_pushed_at_order
        when "watcher_count"
          cursors_for_watcher_count_order
        when "created_at"
          cursors_for_created_at_order
        else
          cursors_for_id_order
        end
      end

      def scope_for_repository_stars
        scope = @items.stars.repositories.order(created_at: :desc, id: :desc).limit(LIMIT)
        scope = scope.where("starrable_id IN (?)", @repository_database_ids) if @repository_database_ids.present?
        scope
      end

      def cursors_for_created_at_order
        return @cursors_for_created_at_order if defined?(@cursors_for_created_at_order)

        cursor_by_repository_id = {}
        scope_for_repository_stars.pluck(:starrable_id, :created_at, :id).each do |(starrable_id, created_at, id)|
          cursor_by_repository_id[starrable_id] = OrderedByDateTimeCursor.new(created_at, id)
        end

        cursors = []
        cursor_by_repository_id.keys.each_slice(BATCH_SIZE) do |repository_ids|
          # Keep the original order from the database
          (repository_ids & permissible_repository_scope(repository_ids).ids).each do |permissible_repository_id|
            cursors << cursor_by_repository_id[permissible_repository_id]
          end
        end

        cursors.reverse! if @order_by[:direction] == "ASC"

        @cursors_for_created_at_order = cursors
      end

      def cursors_for_watcher_count_order
        return @cursors_for_watcher_count_order if defined?(@cursors_for_watcher_count_order)

        star_id_by_repository_id = scope_for_repository_stars.pluck(:starrable_id, :id).to_h

        cursors = []
        star_id_by_repository_id.keys.each_slice(BATCH_SIZE) do |repository_ids|
          permissible_repository_scope(repository_ids).pluck(:watcher_count, :id).each do |watcher_count, repository_id|
            cursors << OrderedByWatcherCountCursor.new(watcher_count, star_id_by_repository_id[repository_id])
          end
        end

        cursors.sort!
        cursors.reverse! if @order_by[:direction] == "DESC"

        @cursors_for_watcher_count_order = cursors
      end

      def cursors_for_pushed_at_order
        return @cursors_for_pushed_at_order if defined?(@cursors_for_pushed_at_order)

        star_id_by_repository_id = scope_for_repository_stars.pluck(:starrable_id, :id).to_h

        cursors = []
        star_id_by_repository_id.keys.each_slice(BATCH_SIZE) do |repository_ids|
          permissible_repository_scope(repository_ids).pluck(:pushed_at, :id).each do |pushed_at, repository_id|
            if pushed_at
              cursors << OrderedByDateTimeCursor.new(pushed_at, star_id_by_repository_id[repository_id])
            end
          end
        end

        cursors.sort!
        cursors.reverse! if @order_by[:direction] == "DESC"

        @cursors_for_pushed_at_order = cursors
      end

      def cursors_for_id_order
        return @cursors_for_id_order if defined?(@cursors_for_id_order)

        cursor_by_repository_id = {}
        scope_for_repository_stars.pluck(:starrable_id, :id).each do |(starrable_id, id)|
          cursor_by_repository_id[starrable_id] = OrderedByIdCursor.new(id)
        end

        cursors = []
        cursor_by_repository_id.keys.each_slice(BATCH_SIZE) do |repository_ids|
          permissible_repository_scope(repository_ids).ids.each do |permissible_repository_id|
            cursors << cursor_by_repository_id[permissible_repository_id]
          end
        end

        cursors.sort!
        cursors.reverse! if @order_by[:direction] == "DESC"

        @cursors_for_id_order = cursors
      end

      def permissible_repository_scope(repository_ids)
        permissible_repository_scope = context[:permission].filtered_permissible_repository_scope(
          @items,
          repository_ids,
          resource: "metadata",
          include_repos_from_enterprise_managed_business: emu_internal_star_visibilty_enabled?
        )
        permissible_repository_scope = permissible_repository_scope.active.filter_spam_and_disabled_for(context[:viewer])

        case @owned_by_viewer
        when true
          permissible_repository_scope = permissible_repository_scope.owned_by(context[:viewer])
        when false
          permissible_repository_scope = permissible_repository_scope.not_owned_by(context[:viewer])
        end

        unless @owned_by_viewer == true
          # If there's no condition on `owner_id` (via the `#owned_by` call above),
          # we should force MySQL to use the primary key index. Any other index is going to cause this
          # query to run for a very long time and time out.
          permissible_repository_scope = permissible_repository_scope.from("`repositories` FORCE INDEX (PRIMARY)")
        end

        if context[:unauthorized_organization_ids].present?
          permissible_repository_scope = permissible_repository_scope.where("repositories.owner_id NOT IN (?)", context[:unauthorized_organization_ids])
        end

        type_scope = repository_type_scope
        if type_scope
          permissible_repository_scope = permissible_repository_scope.merge(type_scope)
        end

        permissible_repository_scope
      end

      def repository_type_scope
        base_scope = ::Repository
        case @type
        when "public" then base_scope.public_scope
        when "private" then base_scope.private_scope
        when "source" then base_scope.not_archived_scope.not_forks
        when "fork" then base_scope.not_archived_scope.forks
        when "mirror" then base_scope.not_archived_scope.joins(:mirror)
        when "template" then base_scope.not_archived_scope.templates
        when "sponsorable" then base_scope.with_sponsorable_owner
        end
      end

      def cursors_type
        case @order_by[:field]
        when "pushed_at", "created_at"
          OrderedByDateTimeCursor
        when "watcher_count"
          OrderedByWatcherCountCursor
        else
          OrderedByIdCursor
        end
      end

      def cursors_for_current_page
        load_data

        @cursors_for_current_page
      end

      def load_data
        return if @loaded
        @loaded = true

        @has_next_page = @has_previous_page = false

        @cursors_for_current_page = cursors_for_given_order

        if @cursors_for_current_page.present?
          if before
            if cursor = cursors_type.decode(before)
              cursor_offset = if @order_by[:direction] == "ASC"
                @cursors_for_current_page.bsearch_index { |c| c >= cursor }
              else
                @cursors_for_current_page.bsearch_index { |c| c <= cursor }
              end

              if cursor_offset
                @has_next_page = cursor_offset < @cursors_for_current_page.length
                @cursors_for_current_page = @cursors_for_current_page[0...cursor_offset]
              end
            else
              @cursors_for_current_page = []
            end
          end

          if after
            if cursor = cursors_type.decode(after)
              cursor_offset = if @order_by[:direction] == "ASC"
                @cursors_for_current_page.bsearch_index { |c| c > cursor }
              else
                @cursors_for_current_page.bsearch_index { |c| c < cursor }
              end

              if cursor_offset
                @has_previous_page = cursor_offset > 0
                @cursors_for_current_page = @cursors_for_current_page[cursor_offset..-1]
              else
                @cursors_for_current_page = []
              end
            else
              @cursors_for_current_page = []
            end
          end
        end

        if first && @cursors_for_current_page.size > first
          @cursors_for_current_page = @cursors_for_current_page.first(first)
          @has_next_page = true
        end

        if last && @cursors_for_current_page.size > last
          @cursors_for_current_page = @cursors_for_current_page.last(last)
          @has_previous_page = true
        end
      end

      private def emu_internal_star_visibilty_enabled?
        if GitHub.multi_tenant_enterprise?
          ::FeatureFlag.vexi.enabled?(:emu_internal_star_visibility, context[:viewer], default: false)
        else
          ::FeatureFlag.vexi.enabled?(:emu_non_multi_tenant_internal_star_visibility, context[:viewer], default: false)
        end
      end
    end
  end
end
