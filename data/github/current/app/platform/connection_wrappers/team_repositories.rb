# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class TeamRepositories < ConnectionWrappers::Base
      class OrderedByIdCursor
        def self.decode(opaque)
          new *Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(opaque)
        end

        def initialize(repository_id)
          @repository_id = repository_id
        end

        attr_reader :repository_id

        include Comparable

        def <=>(other)
          @repository_id <=> other.repository_id
        end

        def encode
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([@repository_id], version: :v2)
        end
      end

      # Cursor for ordering by `CREATED_AT`, `UPDATED_AT`, `PUSHED_AT`
      class OrderedByDateTimeCursor < OrderedByIdCursor
        def self.decode(opaque)
          values = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(opaque)

          new DateTime.iso8601(values[0].to_s), values[1]
        end

        def initialize(datetime, repository_id)
          super repository_id

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
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([@datetime&.iso8601, @repository_id], version: :v2)
        end
      end

      # Cursor for ordering by `STARGAZERS`
      class OrderedByWatcherCountCursor < OrderedByIdCursor
        def initialize(watcher_count, repository_id)
          super repository_id

          @watcher_count = watcher_count
        end

        attr_reader :watcher_count

        def <=>(other)
          result = @watcher_count <=> other.watcher_count
          return result unless result.zero?

          super other
        end

        def encode
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([@watcher_count, @repository_id], version: :v2)
        end
      end

      # Cursor for ordering by `PERMISSION`
      class OrderedByPermissionCursor < OrderedByIdCursor
        def initialize(action, repository_id)
          super repository_id

          @action = action
        end

        attr_reader :action

        def <=>(other)
          result = @action <=> other.action
          return result unless result.zero?

          super other
        end

        def encode
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([@action, @repository_id], version: :v2)
        end
      end

      # Cursor for ordering by `NAME`
      class OrderedByNameCursor < OrderedByIdCursor
        def initialize(repository_name, repository_id)
          super repository_id

          @repository_name = repository_name
        end

        attr_reader :repository_name

        def <=>(other)
          result = @repository_name.casecmp(other.repository_name)
          return result unless result.zero?

          super other
        end

        def encode
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([@repository_name, @repository_id], version: :v2)
        end
      end

      # TODO: Drop once we upgrade to `grapqhl@1.11.0`
      class Edge
        attr_reader :node

        def initialize(node, connection)
          @connection = connection
          @node = node
        end

        def parent
          @connection.parent
        end

        def cursor
          @cursor ||= @connection.cursor_for(@node)
        end
      end

      def initialize(items, field:, affiliation:, order_by: nil, query: nil, **args)
        super items, max_page_size: Schema::DEFAULT_MAX_PER_PAGE, **args

        @affiliation = affiliation
        @order_by = order_by || { field: "id", direction: "ASC" }
        @query = query
        @async_loaded = false
      end

      def parent
        @items
      end

      def nodes
        async_cursors_for_current_page.then do |cursors|
          @nodes ||= if cursors.any?
            Platform::Loaders::ActiveRecord.load_all(::Repository, cursors.map(&:repository_id))
          else
            ::Promise.resolve([])
          end
        end
      end

      def has_next_page
        async_load_data.then do
          @async_has_next_page
        end
      end

      def has_previous_page
        async_load_data.then do
          @async_has_previous_page
        end
      end

      def start_cursor
        async_cursors_for_current_page.then do |cursors|
          cursors.first&.encode
        end
      end

      def end_cursor
        async_cursors_for_current_page.then do |cursors|
          cursors.last&.encode
        end
      end

      def cursor_for(node)
        case @order_by[:field]
        when "watcher_count"
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.watcher_count, node.id], version: :v2)
        when "created_at"
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.created_at.iso8601, node.id], version: :v2)
        when "updated_at"
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.updated_at.iso8601, node.id], version: :v2)
        when "pushed_at"
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.pushed_at.iso8601, node.id], version: :v2)
        when "name"
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.name, node.id], version: :v2)
        when "action"
          action = T.let(T.let("", T.untyped), T.untyped)
          action_list = Ability.where(actor_id: expanded_team_ids_for_affiliation, actor_type: "Team", subject_id: node.id, subject_type: "Repository").pluck(:action)

          action_list.each do |a|
            if action.empty?
              action = a
            else
              action = T.must(Ability.actions[action]) > T.must(Ability.actions[a]) ? action : a
            end
          end

          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([action && Ability.actions[action], node.id], version: :v2)
        else
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor([node.id], version: :v2)
        end
      end

      def total_count
        async_cursors_for_given_order.then do |cursors|
          cursors.size
        end
      end

      private

      def async_cursors_for_given_order
        @async_cursors ||= case @order_by[:field]
        when "action"
          async_cursors_for_action_order
        when "created_at"
          async_cursors_for_column_order(:created_at, OrderedByDateTimeCursor)
        when "pushed_at"
          async_cursors_for_column_order(:pushed_at, OrderedByDateTimeCursor)
        when "updated_at"
          async_cursors_for_column_order(:updated_at, OrderedByDateTimeCursor)
        when "name"
          async_cursors_for_column_order(:name, OrderedByNameCursor)
        when "watcher_count"
          async_cursors_for_column_order(:watcher_count, OrderedByWatcherCountCursor)
        else
          async_cursors_for_id_order
        end
      end

      def expanded_team_ids_for_affiliation
        case @affiliation
        when :immediate
          [@items.id]
        when :inherited
          @items.ancestor_ids
        when :all
          @items.id_and_ancestor_ids
        end
      end

      def async_affiliated_abilities_scope
        @items.async_batch_affiliated_abilities(@affiliation, @order_by[:direction])
      end

      def async_cursors_for_action_order
        async_affiliated_abilities_scope.then do |abilities|
          # abilities here is sorted in the desired order by subject_id only
          # so, build a hash ordered first by ability, then subject_id
          ordered_action_by_repository_id = {}
          actions_list = Ability.actions.values.sort
          actions_list.reverse! if @order_by[:direction] == "DESC"
          actions_list.each do |curr_action|
            abilities.each do |ability|
              action = Ability.actions[ability.action]
              next unless action == curr_action
              if existing = ordered_action_by_repository_id[ability.subject_id]
                ordered_action_by_repository_id[ability.subject_id] = action if action > existing
              else
                ordered_action_by_repository_id[ability.subject_id] = action
              end
            end
          end

          ordered_repository_ids = ordered_action_by_repository_id.keys

          public_repository_ids = []
          private_repository_ids = []

          async_org_repositories.then do |repos|
            repos.each do |public, id|
              if public
                public_repository_ids << id
              else
                private_repository_ids << id
              end
            end

            # If there is a viewer, `async_org_repositories` will include private repositories and we need
            # to filter ids down to those actually accessible by the viewer
            async_accessible_repository_ids_from_private_repository_ids(private_repository_ids).then do |accessible_repository_ids|
              ordered_repository_ids &= public_repository_ids + accessible_repository_ids

              if (oauth_app = context[:oauth_app])
                ordered_repository_ids &= ::Repository.oauth_app_policy_approved_repository_ids(
                  repository_ids: ordered_repository_ids, app: oauth_app,
                )
              end

              ordered_repository_ids.map do |repository_id|
                OrderedByPermissionCursor.new(ordered_action_by_repository_id[repository_id], repository_id)
              end
            end
          end
        end
      end

      def async_cursors_for_id_order
        ordered_repository_ids = T.let([], T::Array[T.untyped])
        public_repository_ids = T.let([], T::Array[T.untyped])
        private_repository_ids = T.let([], T::Array[T.untyped])

        async_org_repositories(order_by: { id: @order_by[:direction] }).then do |repos|
          repos.each do |public, id|
            ordered_repository_ids << id

            if public
              public_repository_ids << id
            else
              private_repository_ids << id
            end
          end

          async_affiliated_abilities_scope.then do |abilities|
            repository_ids_accessible_by_team = abilities.pluck(:subject_id)

            public_repository_ids &= repository_ids_accessible_by_team
            private_repository_ids &= repository_ids_accessible_by_team

            async_accessible_repository_ids_from_private_repository_ids(private_repository_ids).then do |accessible_repository_ids|
              ordered_repository_ids &= public_repository_ids + accessible_repository_ids

              if (oauth_app = context[:oauth_app])
                ordered_repository_ids &= ::Repository.oauth_app_policy_approved_repository_ids(
                  repository_ids: ordered_repository_ids, app: oauth_app,
                )
              end

              ordered_repository_ids.map do |repository_id|
                OrderedByIdCursor.new(repository_id)
              end
            end
          end
        end
      end

      def async_cursors_for_column_order(column, cursor_klass)
        ordered_column_by_repository_id = {}

        public_repository_ids = T.let([], T::Array[T.untyped])
        private_repository_ids = T.let([], T::Array[T.untyped])

        async_org_repositories(order_by: { column => @order_by[:direction], :id => @order_by[:direction] }, extra_fields: column).then do |repos|
          repos.each do |public, id, data|
            ordered_column_by_repository_id[id] = data

            if public
              public_repository_ids << id
            else
              private_repository_ids << id
            end
          end

          ordered_repository_ids = ordered_column_by_repository_id.keys

          async_affiliated_abilities_scope.then do |abilities|
            repository_ids_accessible_by_team = abilities.pluck(:subject_id)

            public_repository_ids &= repository_ids_accessible_by_team
            private_repository_ids &= repository_ids_accessible_by_team

            async_accessible_repository_ids_from_private_repository_ids(private_repository_ids).then do |accessible_repository_ids|
              ordered_repository_ids &= public_repository_ids + accessible_repository_ids

              if (oauth_app = context[:oauth_app])
                ordered_repository_ids &= ::Repository.oauth_app_policy_approved_repository_ids(
                  repository_ids: ordered_repository_ids, app: oauth_app,
                )
              end

              ordered_repository_ids.map do |repository_id|
                cursor_klass.new(ordered_column_by_repository_id[repository_id], repository_id)
              end
            end
          end
        end
      end

      # For a given list of private repository ids, return ids for those repositories
      # that can be accessed by the current viewer
      def async_accessible_repository_ids_from_private_repository_ids(private_repository_ids)
        return [] unless context[:viewer]
        return private_repository_ids if private_repository_ids.empty?
        return private_repository_ids if GitHub.enterprise? && context[:viewer].site_admin?

        organization = @items.organization

        accessible_repository_ids = T.let([], T::Array[T.untyped])
        promises = private_repository_ids.map do |repository_id|
          context[:viewer].async_associated_repository?(
            repository_id,
            include_oauth_restriction: false,
            including: [:direct, :indirect],
            include_indirect_forks: false,
            include_oopfs: false,
            organization: organization)
        end
        Promise.all(promises).then do |accessiblities|
          accessiblities.each_with_index do |accessible, index|
            accessible_repository_ids << private_repository_ids[index] if accessible
          end

          if organization.supports_internal_repositories? && context[:viewer].business_ids.include?(organization.business.id)
            accessible_repository_ids |= private_repository_ids & organization.internal_repositories.ids
          end

          ProgrammaticActor::RepositoryFilter.perform(
            actor: context[:viewer], repository_ids: accessible_repository_ids
          )
        end
      end

      # returns an array of Promise for an array of [public, id] arrays, one for each org repository
      def async_org_repositories(order_by: nil, extra_fields: [])
        @items.organization.async_batch_repositories_for_team_repo_connection(context[:viewer], @query, order_by, extra_fields)
      end

      def cursors_type
        case @order_by[:field]
        when "pushed_at", "created_at", "updated_at"
          OrderedByDateTimeCursor
        when "watcher_count"
          OrderedByWatcherCountCursor
        when "action"
          OrderedByPermissionCursor
        when "name"
          OrderedByNameCursor
        else
          OrderedByIdCursor
        end
      end

      def async_cursors_for_current_page
        async_load_data.then do
          @async_cursors_for_current_page
        end
      end

      def async_load_data
        async_cursors_for_given_order.then do |cursors|
          next if @async_loaded
          @async_loaded = true
          @async_cursors_for_current_page = cursors
          @async_has_next_page = @async_has_previous_page = false

          if before
            cursor = cursors_type.decode(before)

            cursor_offset = if @order_by[:direction] == "ASC"
              @async_cursors_for_current_page.bsearch_index { |c| c >= cursor }
            else
              @async_cursors_for_current_page.bsearch_index { |c| c <= cursor }
            end

            if cursor_offset
              @async_has_next_page = cursor_offset < @async_cursors_for_current_page.length
              @async_cursors_for_current_page = @async_cursors_for_current_page[0...cursor_offset]
            end
          end

          if after
            cursor = cursors_type.decode(after)

            cursor_offset = if @order_by[:direction] == "ASC"
              @async_cursors_for_current_page.bsearch_index { |c| c > cursor }
            else
              @async_cursors_for_current_page.bsearch_index { |c| c < cursor }
            end

            if cursor_offset
              @async_has_previous_page = cursor_offset > 0
              @async_cursors_for_current_page = @async_cursors_for_current_page[cursor_offset..-1]
            else
              @async_cursors_for_current_page = []
            end
          end

          if first && @async_cursors_for_current_page.size > first
            @async_cursors_for_current_page = @async_cursors_for_current_page.first(first)
            @async_has_next_page = true
          end

          if last && @async_cursors_for_current_page.size > last
            @async_cursors_for_current_page = @async_cursors_for_current_page.last(last)
            @async_has_previous_page = true
          end
        end
      end
    end
  end
end
