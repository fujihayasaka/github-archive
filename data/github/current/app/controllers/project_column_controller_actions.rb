# typed: false
# frozen_string_literal: true

module ProjectColumnControllerActions
  include PlatformHelper

  ProjectColumnAddQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectId: ID!) {
      node(id: $projectId) {
        ...Views::ProjectColumns::Add::Project
      }
    }
  GRAPHQL

  ProjectWorkflowsEditQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectColumnId: ID!) {
      node(id: $projectColumnId) {
        ... on ProjectColumn {
          project {
            ...Views::ProjectWorkflows::Edit::Project
          }

          ...Views::ProjectWorkflows::Edit::ProjectColumn
        }
      }
    }
  GRAPHQL

  ShowProjectColumnQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectColumnId: ID!, $archivedStates: [ProjectCardArchivedState]!) {
      node(id: $projectColumnId) {
        ... on ProjectColumn {
          project {
            ...Views::ProjectColumns::ProjectColumn::Project
          }

          ...Views::ProjectColumns::ProjectColumn::ProjectColumn
        }
      }
    }
  GRAPHQL

  def render_show_column(project:, column_id: nil)
    column_id ||= project.columns.find(params[:id]).global_relay_id

    data = platform_execute(ShowProjectColumnQuery, variables: {
      projectColumnId: column_id,
      archivedStates: ["NOT_ARCHIVED"],
    })
    project_column = data.node

    respond_to do |format|
      format.html do
        render partial: "project_columns/project_column", locals: {
          project: project_column.project,
          project_column: project_column,
        }
      end
    end
  end

  CreateProjectColumnQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $columnName: String!, $columnPurpose: ProjectColumnPurpose, $archivedStates: [ProjectCardArchivedState]!) {
      addProjectColumn(input: { projectId: $projectId, name: $columnName, purpose: $columnPurpose }) {
        columnEdge {
          column: node {
            id
            name
            resourcePath

            project {
              ...Views::ProjectColumns::ProjectColumn::Project
            }

            ...Views::ProjectColumns::ProjectColumn::ProjectColumn
          }
        }
      }
    }
  GRAPHQL

  AddProjectWorkflowQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($triggerType: ProjectWorkflowTriggerType!,$projectColumnId: ID!) {
      addProjectWorkflow(input: { triggerType: $triggerType, projectColumnId: $projectColumnId }) {
        projectColumn {
          id
        }
      }
    }
  GRAPHQL

  DeleteProjectWorkflowQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectWorkflowId: ID!) {
      deleteProjectWorkflow(input: { projectWorkflowId: $projectWorkflowId }) {
        __typename # A selection is grammatically required here
      }
    }
  GRAPHQL

  def create_project_column(project:)
    variables = {
      projectId: project.global_relay_id,
      columnName: column_params[:name],
      archivedStates: ["NOT_ARCHIVED"],
    }

    if purpose = column_params[:purpose]
      variables[:columnPurpose] = purpose.present? ? purpose : nil
    end

    project_column_data = platform_execute(CreateProjectColumnQuery, variables: variables)

    if project_column_data.errors.any?
      respond_to do |format|
        format.html do
          project_data = platform_execute(ProjectColumnAddQuery, variables: { projectId: project.global_relay_id })
          render partial: "project_columns/add", locals: {
            project: project_data.node,
            errors: project_column_data.errors,
          }
        end
      end
    else
      project_column = project_column_data.add_project_column.column_edge.column
      update_project_workflows(project, project_column)
      project.notify_subscribers(action: "column_create")
      render_show_column(project: project, column_id: project_column.id)
    end
  end

  UpdateProjectColumnQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectColumnId: ID!, $columnName: String!, $columnPurpose: ProjectColumnPurpose, $archivedStates: [ProjectCardArchivedState]!) {
      updateProjectColumn(input: { projectColumnId: $projectColumnId, name: $columnName, purpose: $columnPurpose }) {
        column: projectColumn {
          id
          name
          resourcePath
          project {
            ...Views::ProjectColumns::ProjectColumn::Project
          }

          ...Views::ProjectColumns::ProjectColumn::ProjectColumn
        }
      }
    }
  GRAPHQL

  def update_project_column(project:)
    project_column = project.columns.find(params[:id])

    project_column_data = platform_execute(UpdateProjectColumnQuery, variables: {
      projectColumnId: project_column.global_relay_id,
      columnName: column_params[:name],
      archivedStates: ["NOT_ARCHIVED"],
    })

    if project_column_data.errors.any?
      respond_to do |format|
        format.html do
          render partial: "project_columns/edit", locals: {
            column_name: project_column.name,
            column_id: project_column.id,
            column_resource_path: project_column_path(project, project_column),
            errors: project_column_data.errors,
          }
        end
      end
    else
      render_show_column(project: project, column_id: project_column.global_relay_id)
    end
  end

  def update_project_column_workflow(project:)
    project_column = project.columns.find(params[:id])
    purpose = column_params[:purpose]

    project_column_data = platform_execute(UpdateProjectColumnQuery, variables: {
      projectColumnId: project_column.global_relay_id,
      # TODO Remove once name is optional
      columnName: project_column.name,
      columnPurpose: purpose.present? ? purpose : nil,
      archivedStates: ["NOT_ARCHIVED"],
    })

    if project_column_data.errors.any?
      respond_to do |format|
        format.html do
          edit_data = platform_execute(ProjectWorkflowsEditQuery, variables: {
            projectColumnId: project_column.global_relay_id,
          })
          render partial: "project_workflows/edit", locals: {
            project_column: edit_data.node,
            project: edit_data.node.project,
            errors: project_column_data.errors,
          }
        end
      end
    else
      project_column = project_column_data.update_project_column.column
      update_project_workflows(project, project_column)
      render_show_column(project: project, column_id: project_column.id)
    end
  end

  def reorder_project_columns(project:)
    project_column = project.columns.find(params[:column_id])
    after = project.columns.find_by_id(params[:previous_column_id])

    if params[:keyboard_move].present?
      GitHub.dogstats.increment("project.keyboard_move", tags: ["target:column"])
    end

    project.move_column(project_column, after: after)
    project.notify_subscribers(
      action: "column_reorder",
      column_url: project_column_path(project, project_column),
      column_id: project_column.id,
      previous_column_id: after.try(:id),
    )

    head :ok
  end

  AutomationOptionsColumnQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectColumnId: ID!) {
      node(id: $projectColumnId) {
        ... on ProjectColumn {
          project {
            ...Views::ProjectWorkflows::Form::Project
          }

          purpose
          ...Views::ProjectWorkflows::Form::ProjectColumn
        }
      }
    }
  GRAPHQL

  AutomationOptionsProjectQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectId: ID!) {
      node(id: $projectId) {
        ...Views::ProjectWorkflows::Form::Project
      }
    }
  GRAPHQL

  def render_project_column_automation_options(project:)
    project_column = if params[:id].present?
      column = project.columns.find(params[:id])
      data = platform_execute(AutomationOptionsColumnQuery, variables: {
        projectColumnId: column.global_relay_id,
      })
      data.node
    else
      nil
    end

    project_node = if project_column.present?
      project_column.project
    else
      data = platform_execute(AutomationOptionsProjectQuery, variables: {
        projectId: project.global_relay_id,
      })
      data.node
    end

    purpose = params[:purpose] || project_column&.purpose

    respond_to do |format|
      format.html do
        render partial: "project_workflows/form", locals: {
          project: project_node,
          project_column: project_column,
          purpose: purpose,
        }
      end
    end
  end

  DeleteProjectColumnQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($columnId: ID!) {
      deleteProjectColumn(input: { columnId: $columnId }) {
        __typename # A selection is grammatically required here
      }
    }
  GRAPHQL

  def destroy_project_column(project:)
    project_column = project.columns.find(params[:id])
    mutation = platform_execute(DeleteProjectColumnQuery, variables: { columnId: project_column.global_relay_id })
    if mutation.errors.any?
      return render json: { errors: mutation.errors.messages.values.join(", ") }, status: :unprocessable_entity
    end

    this_project.notify_subscribers(
      action: "column_destroyed",
    )
    head :ok
  end

  def archive_project_column(project:)
    project_column = project.columns.find(params[:id])
    project_column.archive_all_cards(actor: current_user)

    head :ok
  end

  private

  def update_project_workflows(project, project_column)
    if automation_options = column_params[:automation_options]
      automation_options.each do |opt|
        vars = {
          projectColumnId: project_column.id,
          triggerType: opt,
        }
        data = platform_execute(AddProjectWorkflowQuery, variables: vars)
      end
    end

    workflow_ids = column_params[:workflow_ids] || []
    checked_workflow_ids = column_params[:checked_workflow_ids] || []

    delete_ids = workflow_ids - checked_workflow_ids
    delete_ids.each do |id|
      data = platform_execute(DeleteProjectWorkflowQuery, variables: { projectWorkflowId: id })
    end
    project.notify_subscribers(action: "column_automation_updated", message: "#{project_column.name}'s automation was updated")
    project.notify_metadata_subscribers # presence of automation changes the open/close project UI
  end

  def column_params
    params.require(:project_column).permit(:name, :purpose, :automation, workflow_ids: [], checked_workflow_ids: [], automation_options: [])
  end
end
