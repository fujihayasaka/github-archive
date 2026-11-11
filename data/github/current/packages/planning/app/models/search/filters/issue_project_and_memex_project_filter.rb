# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # An issue project filter is used to limit search results to issues that
    # are attached to cards in a particular project. The document must contain
    # a `projects` field in order for this filter to be used.
    class IssueProjectAndMemexProjectFilter < ::Search::Filter
      # Create a new ProjectFilter.
      #
      # opts - The options Hash
      #
      def initialize(opts = {})
        super(opts)

        @current_user = options.fetch(:current_user, nil)
        @execution = opts[:execution] || :and
        map_bool_collection
      end

      def invalid_reason
        "An invalid project was specified."
      end

      def must
        build(project_bool_collection.must, memex_bool_collection.must, :must)
      end

      # Returns a filter Hash that can be used in the `must_not` portion of an ES
      # boolean filter.
      def must_not
        build(project_bool_collection.must_not, memex_bool_collection.must_not, :must_not)
      end

      # Returns a filter Hash that can be used in the `should` portion of an ES
      # boolean filter.
      # This filter doesn't support a `should` filters
      #
      # Returns nil
      def should
        build(project_bool_collection.should, memex_bool_collection.should, :should)
      end

      # Returns `true` if all of the components (must, must_not, should) are
      # empty. Returns `false` if any one of the components contains data.
      def blank?
        project_bool_collection.blank? && memex_bool_collection.blank?
      end

      # Internal: Build a filter Hash from the given set of values.

      # values - The Array of values from which to build the filter

      # Returns a filter Hash or nil.
      def build(project_values, memex_values, filter_type)
        return if project_values.blank? && memex_values.blank?

        if project_values.first == :missing || memex_values.first == :missing
          { bool: { must_not: [
            { exists: { field: :memex_project_ids } },
            { exists: { field: :project_ids } }
            ] } }
        elsif project_values.first == Filter::EXISTS || memex_values.first == Filter::EXISTS
          { bool: { should: [
            build_exists_filter(:project_ids),
            build_exists_filter(:memex_project_ids),
          ] } }
        else
          filter = nil
          if project_values.present? && memex_values.blank?
            filter = build_term_filter(:project_ids, project_values, execution: @execution)
          elsif memex_values.present? && project_values.blank?
            filter = build_term_filter(:memex_project_ids, memex_values, execution: @execution)
          elsif project_values.present? && memex_values.present?
            project_filter = build_term_filter(:project_ids, project_values, execution: @execution)
            memex_filter = build_term_filter(:memex_project_ids, memex_values, execution: @execution)

            # From here on we combine the results from the two filters and we create
            # a list of term filters. The output of build_term_filter is either 1 term
            # or a structure like `filter` below, with terms on the spot of the empty array.
            if @execution == :and
              filter = { bool: { must: [] } }

              # If project_values or memex_values is a scalar or array with 1 element, then
              # build_term_filter returns a singular :term. If one of those contains an array
              # with multiple values, the result is of the form { bool: { must: [] } }, also
              # returned by build_term_filter.
              filter[:bool][:must] += project_filter[:bool][:must] if project_filter.key? :bool
              filter[:bool][:must] << project_filter if project_filter.key? :term
              filter[:bool][:must] += memex_filter[:bool][:must] if memex_filter.key? :bool
              filter[:bool][:must] << memex_filter if memex_filter.key? :term
            else
              filter = []

              # If project_values or memex_values is a scalar or array with 1 element, then
              # build_term_filter returns a singular :term. If one of those contains an array
              # with multiple values, the result is of the form { bool: { must: [] } }, also
              # returned by build_term_filter.
              filter += project_filter[:bool][:must] if project_filter.key? :bool
              filter << project_filter if project_filter.key? :term
              filter += memex_filter[:bool][:must] if memex_filter.key? :bool
              filter << memex_filter if memex_filter.key? :term
            end
          end

          # Choose between a must or should bool-filter. For must, we use must in
          # ES syntax, which is logical AND. For must_not, we use should in
          # ES syntax, which is logical OR. For a must_not filter, our returned
          # filter gets negated later, which means we end up with NOT (x OR y),
          # and not NOT (x AND y), which is incorrect.
          if filter_type == :must_not && filter && filter.key?(:bool)
            filter[:bool][:should] = filter[:bool].delete :must
          end

          filter
        end
      end

      # Internal: A filter uses a boolean collection to keep accumulate and
      # transform values before finally using them in building the filter Hash.
      #
      # Returns this filter's BoolCollection.
      def project_bool_collection
        return @project_bool_collection if defined? @project_bool_collection
        @project_bool_collection = bool_collection.dup
        @project_bool_collection
      end

      # Internal: A filter uses a boolean collection to keep accumulate and
      # transform values before finally using them in building the filter Hash.
      #
      # Returns this filter's BoolCollection.
      def memex_bool_collection
        return @memex_bool_collection if defined? @memex_bool_collection
        @memex_bool_collection = bool_collection.dup
        @memex_bool_collection
      end

      # Interal: Override the superclass method and make it a noop
      # implementation. Mapping the boolean collection is not applicable for
      # the issue project filter.
      #
      # Returns this filter's boolean collection.
      def map_bool_collection
        return nil if defined? @mapped
        @mapped = true

        # project_bool_collection and memex_bool_collection start of with the same contents, so
        # we check only for the contents of one of them.
        if project_bool_collection.must && project_bool_collection.must.include?(:missing)
          project_bool_collection.clear
          project_bool_collection.must(:missing)

          memex_bool_collection.clear
          memex_bool_collection.must(:missing)
        elsif project_bool_collection.must && project_bool_collection.must.include?(Filter::EXISTS)
          project_bool_collection.clear
          project_bool_collection.must(Filter::EXISTS)

          memex_bool_collection.clear
          memex_bool_collection.must(Filter::EXISTS)
        else
          # project_bool_collection and memex_bool_collection start the same and we filter their contents
          # for either classic or memex projects. A correct project for one of the collections will not show
          # in the other collection, but we can have items which are not valid for either.
          #
          # So we need the size of one of the collections and we check later if the combined filtered results have
          # the same length.
          pre_filtered_values = project_bool_collection.all.size

          project_bool_collection.map_all! do |val|
            project = project_from(val)
            project && project.id
          end

          memex_bool_collection.map_all! do |val|
            project = memex_project_from(val)
            project && project.id
          end

          # If we've lost any values after filtering, it means at least one of them was invalid. We need to add
          # the size of both of the collections together as they have mutually exclusive values after filtering.
          @valid = false if pre_filtered_values > (project_bool_collection.all.size + memex_bool_collection.all.size)
        end

        nil
      end

      private

      def project_from(value)
        param = ProjectQueryParam.new(param: value)
        return unless param.valid?

        project_owner = if param.repository_project?
          Repository.with_name_with_owner(param.owner_display_login, param.repository_name)
        else
          User.find_by(login: param.owner_display_login)
        end

        return unless project_owner

        project = project_owner.projects.find_by(number: param.number)
        project if project&.readable_by?(@current_user)
      end

      def memex_project_from(value)
        param = ProjectQueryParam.new(param: value)
        return unless param.valid?

        project_owner = if param.repository_project?
          # Repository can't be an owner for a memex project.
          return
        else
          User.find_by(login: param.owner_display_login)
        end

        return unless project_owner

        project = project_owner.memex_projects.find_by(number: param.number)
        project if project&.readable_by?(@current_user)
      end
    end
  end
end
