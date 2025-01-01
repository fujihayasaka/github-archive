# typed: true
# frozen_string_literal: true

module MemexProject::TemplatesDependency
  extend T::Helpers
  requires_ancestor { MemexProject }

  def create_template!
    existing_template = MemexTemplate.find_by(memex_project: self)
    if existing_template
      existing_template.update(active: true)
    else
      new_template = MemexTemplate.create!(memex_project: self, active: true)
    end
  end

  def remove_template!
    existing_template = MemexTemplate.find_by(memex_project: self)
    if existing_template
      existing_template.update(active: false)
    end
  end

  # Used for applying a template defined in MemexProject::DefaultTemplates
  # Unlike a user-defined template, default templates do not define custom workflows
  def apply_default_template(creator:, template:)
    # Handle feature flag for team planning template - update views and images if feature flag is enabled
    if template[:id] == "team_planning" && MemexProject::DefaultTemplates::TeamPlanningTemplate.use_updated_template?(creator)
      template = {
        **template,
        views: MemexProject::DefaultTemplates::TeamPlanningTemplate::UPDATED_VIEWS,
        image_url: MemexProject::DefaultTemplates::TeamPlanningTemplate::IMAGE_PATHS[:updated]
      }
    end

    template = template.deep_dup

    # Remove sub-issues-progress field from all template views when feature flag is disabled
    unless FeatureFlag.vexi.enabled?(:memex_new_default_fields, creator, default: false)
      sub_issues_progress_slug = MemexProjectColumn.generate_name_slug(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME)
      template[:views]&.each do |view|
        if view[:visible_fields_by_name]
          view[:visible_fields_by_name].delete(sub_issues_progress_slug)
        end
      end
    end

    # If a template has custom workflows defined, then use those. Otherwise, apply the default workflows.
    apply_template(creator: creator, template: template, use_default_workflows: template[:workflows].blank?)
  end

  def apply_template(creator:, template:, use_default_workflows: false)
    # Before using the template data, we ensure that keys can be strings or symbols, in order
    # to smooth over some inconsistences with how data is exported to the templates and how it
    # is actually accessed and used for creating objects
    template = template.with_indifferent_access

    handle_columns(creator, template[:columns])

    # Normalization has to happen after all the columns are created and persisted to the DB
    # as it using ids of the columns to create the views, workflows and insights
    normalize_template(template)

    if use_default_workflows
      handle_default_workflows(creator)
    else
      handle_workflows(creator, template[:workflows])
    end
    handle_views(creator, template[:views])
    handle_insights(creator, template[:insights])

    # Ensure we clear out any system-defined Type columns from the source project if the target project does not
    # belong to an organization.
    unless owner.organization?
      remove_system_defined_issue_type_columns
    end

    true
  end

  private

  def normalize_template(template)
    # Workflows: transform field and option names to ids
    if template[:workflows]
      template[:workflows].each do |workflow|
        workflow[:actions_attributes].each do |action|
          if action[:arguments][:fieldName]
            field = memex_project_columns.find_by(name_slug: action[:arguments][:fieldName])
            action[:arguments][:fieldId] = field&.id
            action[:arguments].delete(:fieldName)

            if action[:arguments][:fieldOptionName]
              option = field&.settings["options"].find { |option| option["name"] == action[:arguments][:fieldOptionName] }
              action[:arguments][:fieldOptionId] = option&.[]("id")
              action[:arguments].delete(:fieldOptionName)
            end
          end
        end
      end
    end

    # Views: transform column names to ids
    template[:views].each do |view|
      if view[:visible_fields_by_name]
        view[:visible_fields] = view[:visible_fields_by_name].map do |field_name|

          memex_project_columns.find_by(name_slug: field_name.downcase)&.id
        end
        view.delete(:visible_fields_by_name)
      end

      if view[:group_by_fields_by_name]
        view[:group_by] = view[:group_by_fields_by_name].map do |field_name|
          memex_project_columns.find_by(name_slug: field_name.downcase)&.id
        end
        view.delete(:group_by_fields_by_name)
      end

      if view[:sort_by_fields_by_name]
        view[:sort_by] = view[:sort_by_fields_by_name].map do |field_and_sort_order|
          field_name, sort_order = field_and_sort_order
          [memex_project_columns.find_by(name_slug: field_name.downcase)&.id, sort_order]
        end
        view.delete(:sort_by_fields_by_name)
      end

      if view[:column_field_by_name]
        vertical_group_by_field = memex_project_columns.find_by(name_slug: view[:column_field_by_name].first&.downcase)
        if vertical_group_by_field
          view[:vertical_group_by] = [vertical_group_by_field.id]
        end

        view.delete(:column_field_by_name)
      end

      if view[:slice_by_field_by_name]
        slice_by = view[:slice_by_field_by_name].deep_dup
        slice_by_field = memex_project_columns.find_by(name_slug: slice_by[:field_name]&.downcase)
        if slice_by_field
          slice_by[:field] = slice_by_field.id
        end

        slice_by.delete(:field_name)
        slice_by.transform_keys!(&:to_s)
        view[:slice_by] = slice_by
        view.delete(:slice_by_field_by_name)
      end

      # currently only support board, will add roadmap view support in a followup PR
      if view[:layout_settings_by_name]
        layout_settings_by_name = view[:layout_settings_by_name]
        layout_settings = {}

        if (column_limits_by_name = layout_settings_by_name&.dig("board", "column_limits")).present?
          column_limits = column_limits_by_name.reduce({}) do |memo, (name_key, value)|
            if column = memex_project_columns.find_by(name_slug: name_key)
              if column.single_select? || column.iteration?
                memo[column.id.to_s] = value.compact
              end
            end
            memo
          end
          # currently column_limits is the only board setting
          layout_settings["board"] = { "column_limits" => column_limits }
        end

        if (roadmap_settings = layout_settings_by_name&.dig("roadmap")).present?
          if (date_fields = roadmap_settings["date_fields"])
            date_fields = date_fields.map do |field_name|
              memex_project_columns.find_by(name_slug: field_name)&.id
            end.compact

            roadmap_settings["date_fields"] = date_fields
          end

          if (marker_fields = roadmap_settings["marker_fields"])
            marker_fields = marker_fields.map do |field_name|
              memex_project_columns.find_by(name_slug: field_name)&.id
            end.compact

            roadmap_settings["marker_fields"] = marker_fields
          end

          layout_settings["roadmap"] = roadmap_settings
        end

        view[:layout_settings] = layout_settings
        view.delete(:layout_settings_by_name)
      end

      if view[:aggregation_settings_by_name]
        aggregation_settings_by_name = view[:aggregation_settings_by_name]
        aggregation_settings = {}

        aggregation_settings["hide_items_count"] = aggregation_settings_by_name&.dig(:hide_items_count)

        if (sum = aggregation_settings_by_name&.dig(:sum))
          aggregation_settings["sum"] = sum.map do |field_name|
            memex_project_columns.find_by(name_slug: field_name)&.id
          end.compact
        end

        view[:aggregation_settings] = aggregation_settings
        view.delete(:aggregation_settings_by_name)
      end

      view
    end

    # Insights: transform column names to ids
    template[:insights]&.map do |chart|
      x_source = chart[:configuration][:xAxis][:dataSource]
      if x_source.is_a?(Hash)
        if column_name = chart[:configuration][:xAxis][:dataSource].delete(:columnName)
          chart[:configuration][:xAxis][:dataSource][:column] = memex_project_columns
            .find_by(name_slug: column_name&.downcase)
            &.id
        end
      end

      x_group = chart[:configuration][:xAxis][:groupBy]
      if x_group.is_a?(Hash)
        if column_name = chart[:configuration][:xAxis][:groupBy].delete(:columnName)
          chart[:configuration][:xAxis][:groupBy][:column] = memex_project_columns
            .find_by(name_slug: column_name&.downcase)
            &.id
        end
      end

      y_aggregate = chart[:configuration][:yAxis][:aggregate]
      if y_aggregate.is_a?(Hash)
        if column_names = y_aggregate.delete(:columnNames)
          y_columns = column_names.map do |column|
            memex_project_columns.find_by(name_slug: column&.downcase)&.id
          end
          chart[:configuration][:yAxis][:aggregate][:columns] = y_columns
        end
      end

      chart
    end
  end

  def update_status_field(new_column_value)
    status_column&.update(settings: { options: new_column_value[:settings][:options] })
  end

  # If a project's owner or the create is not eligible for issue types, then we need to remove any system-defined issue
  # type columns and their reference in views from the source project before applying the template.
  def remove_system_defined_issue_type_columns
    unallowed_issue_type_columns = memex_project_columns.select(&:issue_type?).to_a
    return unless unallowed_issue_type_columns.any?

    unallowed_issue_type_columns.each(&:destroy!)
    @columns = columns - unallowed_issue_type_columns
  end

  def handle_columns(creator, template_columns)
    # If the destination project has any system defined issue_type columns with the same name as any user-defined
    # columns in the source template, then we need to delete the system-defined issue_type columns in the destination
    # project otherwise the user-defined columns will not be created due to conflicting name.
    has_user_defined_type_column_from_source_project = template_columns.any? do |column|
      column[:name].casecmp?(MemexProjectColumn::TYPE_COLUMN_NAME) && column[:user_defined]
    end

    if has_user_defined_type_column_from_source_project
      remove_system_defined_issue_type_columns
    end

    template_specific_column_names = template_columns.map { |c| c[:name] }
    existing_column_names = []
    position = 0
    self.columns.each do |column|
      existing_column_names << column.name
      position = T.cast(column.position, Integer) if column.position > position
    end

    columns_to_create = template_specific_column_names - existing_column_names
    column_records = template_columns
      .select { |column| columns_to_create.include?(column[:name]) }
      .map.with_index(1) do |column, index|
        self.memex_project_columns.build(
          creator: creator,
          visible: true,
          position: position + index,
          **column
        )
      end

    MemexProjectColumn.transaction do
      column_records.each(&:save!)
    end

    status_field = template_columns.find { |column| column[:name] == MemexProjectColumn::STATUS_COLUMN_NAME }
    if status_field
      update_status_field(status_field)
    end
  end

  def handle_workflows(creator, template_workflows)
    return unless template_workflows

    MemexProjectWorkflow.transaction do
      # When there are custom workflows, then the source of truth should be the specified templates, so we delete
      # all existing ones to ensure the state of the project after applying matches the template.
      self.workflows.destroy_all

      self.workflows.create!(
        template_workflows
          .map do |workflow|
            workflow[:actions_attributes].map! do |action|
              {
                creator: creator,
                **action
              }
            end

            {
              creator: creator,
              **workflow
            }
          end
        )
    end
  end

  def handle_views(creator, views)
    existing = T.must(self.memex_project_views.first)
    existing.assign_attributes(creator: creator, **views.first)

    # Skipping the first view as it is updated above
    views = views.drop(1).map do |view|
      self.memex_project_views.build(
        creator: creator,
        **view
      )
    end

    MemexProjectView.transaction do
      existing.save!
      views.each do |view|
        save_view_with_priority!(view, **{ position: :top })
      end
    end
  end

  def handle_insights(creator, insights)
    MemexProjectChart.transaction do
      insights&.each do |insight|
        chart = self.charts.new(
          creator: creator,
          **insight
        )

        # If the chart is not valid, we are not going to attempt to save it. Since it
        # causes copying to project to fail. Instead, we will destroy the chart since it
        # still makes the project fail to copy due to it being invalid.
        chart.valid? ? chart.save! : chart.destroy
      end
    end
  end

  def handle_default_workflows(creator)
    return unless (status_column = self.status_column)

    default_workflows = MemexProject.default_persisted_workflow_attributes(
      creator: creator,
      status_column: status_column,
    )
    trigger_types = default_workflows.map { |workflow| workflow[:trigger_type] }.uniq
    workflows.with_trigger_type(trigger_types).destroy_all

    self.workflows.create(default_workflows)
  end
end
