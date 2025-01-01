# typed: true
# frozen_string_literal: true

class MemexProject
  # This class will be used to serialize a MemexProject object into a format that can be consumed by
  # MemexProject::Copier. The serialized format will be a hash with the following structure:
  #
  # {
  #   columns:   [], # an array of hashes, one for each column
  #   views:     [], # an array of hashes, one for each view
  #   workflows: [], # an array of hashes, one for each workflow
  # }
  #
  # Configuration that references project-specific column ids are replaced with the column's
  # unique name_slug in a new attribute. For example, a workflow's "fieldId" property is
  # replaced with a "fieldName" property.
  class StructureSerializer

    def initialize(memex_project)
      @project = memex_project
    end

    def serialize
      {
        columns: columns,
        views: views,
        workflows: workflows,
        insights: insights,
      }.compact
    end

    private

    def insights
      @insights ||= @project.supported_charts.map do |chart|
        configuration = chart.configuration.deep_symbolize_keys

        if configuration[:xAxis][:dataSource].is_a?(Hash)
          column = configuration[:xAxis][:dataSource][:column]
          if column.is_a?(Integer)
            configuration[:xAxis][:dataSource][:columnName] = lookup_field_by_id(column)&.name_slug
            configuration[:xAxis][:dataSource].delete(:column)
          end
        end

        if configuration[:xAxis][:groupBy].is_a?(Hash)
          column = configuration[:xAxis][:groupBy][:column]
          if column.is_a?(Integer)
            configuration[:xAxis][:groupBy][:columnName] = lookup_field_by_id(column)&.name_slug
            configuration[:xAxis][:groupBy].delete(:column)
          end
        end

        if configuration[:yAxis][:aggregate].is_a?(Hash)
          columns = configuration[:yAxis][:aggregate][:columns]
          if columns.is_a?(Array) && columns.all? { |c| c.is_a?(Integer) }
            configuration[:yAxis][:aggregate][:columnNames] = columns.map { |c| lookup_field_by_id(c)&.name_slug }
            configuration[:yAxis][:aggregate].delete(:columns)
          end
        end

        {
          name: chart.name,
          number: chart.number,
          configuration: configuration,
        }
      end
    end

    # Within workflow actions' arguments, convert fieldId and fieldOptionId to names so Copier can convert them into
    # new column ids. Preserve all other arguments.
    def workflows
      @workflows ||= @project.workflows.map do |workflow|
        # Don't copy auto-add workflows
        next if workflow.is_auto_add_workflow?

        {
          name: workflow.name,
          trigger_type: workflow.trigger_type,
          enabled: workflow.enabled,
          content_types: workflow.content_types,
          actions_attributes: workflow.actions.map do |action|
            arguments = action.arguments.dup

            if action.arguments["fieldId"]
              arguments[:fieldName] = lookup_field_by_id(action.arguments["fieldId"])&.name_slug
              if action.arguments["fieldOptionId"]
                arguments[:fieldOptionName] = convert_field_option_id_to_name(
                  action.arguments["fieldId"],
                  action.arguments["fieldOptionId"]
                )
              end
              arguments.delete("fieldId")
              arguments.delete("fieldOptionId")
            end

            { action_type: action.action_type, arguments: arguments }
          end
        }
      end.compact
    end

    def columns
      @columns ||= @project.memex_project_columns.map do |column|
        {
          name: column.name,
          data_type: column.data_type.to_sym,
          default_column: column.default_column,
          user_defined: column.user_defined,
          settings: filtered_settings(column),
          visible: column.visible,
        }
      end
    end

    def filtered_settings(column)
      return unless column.settings

      data_type = column.data_type
      column_settings = column.settings.dup

      case data_type
      when "single_select"
        column_settings["options"].map do |option|

          # defaults for options that existed before these fields were added
          if option["description"].nil?
            option["description"] = ""
          end

          if option["color"].nil?
            option["color"] = "GRAY"
          end

          # the id here isn't unique so we can preserve it
          option
        end
      when "iteration"
        iterations = column_settings.dig("configuration", "iterations")
        # the id here isn't unique so we can preserve it
        iterations.map { |iteration| iteration.except!("title_html") }
      end

      column_settings.with_indifferent_access
    end

    def views
      return @views if defined?(@views)

      prioritized_views = @project.prioritized_memex_project_views.reverse
      @views = prioritized_views.map do |view|
        {
          name: view.name,
          visible_fields_by_name: lookup_visible_fields(view),
          layout: view.layout.to_sym,
          filter: view.filter,
          group_by_fields_by_name: lookup_group_by_fields(view),
          sort_by_fields_by_name: lookup_sort_by_fields(view),
          column_field_by_name: lookup_column_field(view),
          aggregation_settings_by_name: lookup_aggregation_settings(view),
          slice_by_field_by_name: lookup_slice_by_field(view),
          layout_settings_by_name: lookup_layout_settings(view),
        }
      end
    end

    # Get the record for a project's column by id
    def lookup_field_by_id(field_id)
      @project.memex_project_columns.find_by(id: field_id)
    end

    # The copied project will have a reference of the column and option ids used to group by elements in the view.
    # Since we are operating on a copy, we cannot use those references anymore, so we look up the names of them.
    def convert_field_option_id_to_name(field_id, field_option_id)
      field = lookup_field_by_id(field_id)
      field.settings_options.find { |option| option["id"] == field_option_id }&.[]("name")
    end

    # The copied project will have a reference of the column ids used to group by elements in the view. Since we
    # are operating on a copy, we cannot use those references anymore, so we look up the names of those fields
    def lookup_group_by_fields(view)
      return [] unless view.group_by

      view.group_by.map do |field_id|
        lookup_field_by_id(field_id)&.name_slug
      end.compact
    end

    def lookup_slice_by_field(view)
      field = view.slice_by&.dig("field")
      return {} unless field

      slice_by_field_by_name = lookup_field_by_id(field)&.name_slug
      return {} unless slice_by_field_by_name

      slice_by_copy = view.slice_by.deep_dup
      slice_by_copy.delete("field")
      slice_by_copy["field_name"] = slice_by_field_by_name
      slice_by_copy.transform_keys!(&:to_sym)
      slice_by_copy
    end

    # The copied project will have a reference of the column ids used to show which fields are visible in the view.
    # Since we are operating on a copy, we cannot use those references anymore, so we look up the names of those fields
    def lookup_visible_fields(view)
      return [] unless view.visible_fields

      view.visible_fields.map do |field_id|
        lookup_field_by_id(field_id)&.name_slug
      end.compact
    end

    # A view's sort_by attribute is an array of arrays that contain the field id and the sort order
    # [[id, "asc"]]
    # The id will not match any of the new fields of the copied project so we need to tally a list of names and
    # when we apply the template, map those to the new fields and store their ids. This is a similar pattern to
    # *_fields_by_name
    def lookup_sort_by_fields(view)
      return [] unless view.sort_by

      view.sort_by.map do |field_and_sort_order|
        field_id, sort_order = field_and_sort_order
        name_slug = lookup_field_by_id(field_id)&.name_slug
        [name_slug, sort_order]
      end
    end

    # A board view's columns, known as "Column Field" in the UI, are determined by the `vertical_group_by` attribute,
    # an array of column ids. Only the first column is used, but the model does support multiple values, so we return
    # an array (though we only ever expect there to be one value).
    def lookup_column_field(view)
      return [] unless view.vertical_group_by.present?

      view.vertical_group_by.map do |field_id|
        lookup_field_by_id(field_id)&.name_slug
      end.compact
    end

    # A board view's layout settings are used to store a column limit, a board column is either a single-select option
    # or an iteration option. Column limits are indexed by the column id, so we need to replace it with the column
    # name so that we can match the limit to the new column when the template is being applied
    def lookup_layout_settings(view)
      layout_settings = view.layout_settings
      layout_settings_by_name = {}
      # currently only support board, will add roadmap support in a followup PR
      if (column_limits = layout_settings&.dig("board", "column_limits")).present?
        column_limits_by_name = column_limits.reduce({}) do |memo, (key, value)|
          if column = @project.memex_project_columns.find_by(id: key)
            if column.single_select? || column.iteration?
              memo[column&.name_slug] = value.compact
            end
          end
          memo
        end

        layout_settings_by_name["board"] = { "column_limits" => column_limits_by_name }
      end

      if layout_settings&.dig("roadmap").present?
        layout_settings_by_name["roadmap"] = layout_settings["roadmap"]
      end

      # for roadmap both date_fields and marker_fields use column ids
      if (date_fields = layout_settings&.dig("roadmap", "date_fields")).present?
        date_fields_by_name = date_fields.map do |field_id|
          lookup_field_by_id(field_id)&.name_slug
        end.compact

        layout_settings_by_name["roadmap"]["date_fields"] = date_fields_by_name
      end

      if (marker_fields = layout_settings&.dig("roadmap", "marker_fields")).present?
        marker_fields_by_name = marker_fields.map do |field_id|
          lookup_field_by_id(field_id)&.name_slug
        end.compact

        layout_settings_by_name["roadmap"]["marker_fields"] = marker_fields_by_name
      end

      layout_settings_by_name
    end

    sig { params(view: MemexProjectView).returns(T::Hash[Symbol, T.untyped]) }
    def lookup_aggregation_settings(view)
      aggregation_settings = T.let(view.aggregation_settings || {}, T::Hash[T.untyped, T.untyped])
      aggregation_settings_by_name = {}

      if aggregation_settings["hide_items_count"].present?
        aggregation_settings_by_name[:hide_items_count] = aggregation_settings["hide_items_count"]
      end
      if aggregation_settings["sum"].present?
        aggregation_settings_by_name[:sum] = aggregation_settings["sum"]&.map do |field_id|
          lookup_field_by_id(field_id)&.name_slug
        end&.compact
      end

      aggregation_settings_by_name
    end
  end
end
