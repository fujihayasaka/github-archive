# typed: strict
# frozen_string_literal: true

module Api::Serializer::ProjectsV2Dependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  # Used for the Projects webhooks implementation
  sig do
    params(
      item: MemexProjectItem,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[String, T.untyped])
  end
  def projects_v2_item_hash(item, options = {})
    options = Api::SerializerOptions.from(options)

    {
      id: item.id,
      node_id: global_id_for(item, options),
      project_node_id: global_id_for(item.memex_project, options),
      content_node_id: global_id_for(item.content, options), # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      content_type: item.content_type,
      creator: simple_user_hash(item.creator, content_options(options)),
      created_at: time(item.created_at),
      updated_at: time(item.updated_at),
      archived_at: time(item.archived_at),
    }
  end

  sig do
    params(
      item: MemexProjectItem,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[String, T.untyped])
  end
  def simple_projects_item_hash(item, options = {})
    options = Api::SerializerOptions.from(options)

    project = T.must(item.memex_project)
    base_path = build_project_base_path(project, options)

    {
      id: item.id,
      node_id: global_id_for(item, options),
      content_type: item.content_type,
      content: get_content_hash_for_item(item, options),
      creator: simple_user_hash(item.creator, content_options(options)),
      created_at: time(item.created_at),
      updated_at: time(item.updated_at),
      archived_at: time(item.archived_at),
      project_url: projects_v2_url_for_owner(project.owner, project.number, options),
      item_url: url("#{base_path}/items/#{item.id}")
    }
  end

  # Used for the Projects webhooks implementation
  sig do
    params(
      project: MemexProject,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[String, T.untyped])
  end
  def projects_v2_hash(project, options = {})
    options = Api::SerializerOptions.from(options)

    {
      id: project.id,
      node_id: global_id_for(project, options),
      owner: simple_user_hash(project.owner, content_options(options)),
      creator: simple_user_hash(project.creator, content_options(options)),
      title: project.title,
      description: project.description,
      public: !!project.public,
      closed_at: time(project.closed_at),
      created_at: time(project.created_at),
      updated_at: time(project.updated_at),
      number: project.number,
      short_description: project.short_description,
      deleted_at: time(project.deleted_at),
      deleted_by: simple_user_hash(project.deleted_by, content_options(options))
    }
  end

  sig do
    params(
      project: MemexProject,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[String, T.untyped])
  end
  def projects_hash(project, options = {})
    options = Api::SerializerOptions.from(options)

    {
      id: project.id,
      node_id: global_id_for(project, options),
      owner: simple_user_hash(project.owner, content_options(options)),
      creator: simple_user_hash(project.creator, content_options(options)),
      title: project.title,
      description: project.description,
      public: !!project.public,
      closed_at: time(project.closed_at),
      created_at: time(project.created_at),
      updated_at: time(project.updated_at),
      number: project.number,
      short_description: project.short_description,
      deleted_at: time(project.deleted_at),
      deleted_by: simple_user_hash(project.deleted_by, content_options(options)),
      state: project.closed? ? "closed" : "open",
      latest_status_update: projects_v2_status_update_hash(project.latest_status_update, options),
      is_template: project.is_template?
    }
  end

  sig do
    params(
      status_update: T.nilable(MemexProjectStatus),
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def projects_v2_status_update_hash(status_update, options = {})
    return unless status_update

    options = Api::SerializerOptions.from(options)

    {
      id: status_update.id,
      node_id: global_id_for(status_update, options),
      project_node_id: global_id_for(status_update.memex_project, options),
      creator: simple_user_hash(status_update.creator, content_options(options)),
      body: status_update.body,
      start_date: status_update.start_date,
      target_date: status_update.target_date,
      status: MemexProjectStatus.status_id_to_enum_string(status_update.status_id),
      created_at: time(status_update.created_at),
      updated_at: time(status_update.updated_at),
    }
  end

  sig do
    params(
      field: MemexProjectColumn::Field::Base,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[String, T.untyped])
  end
  def projects_v2_fields_hash(field, options = {})
    options = Api::SerializerOptions.from(options)

    project = T.must(field.memex_project)

    field_data = {
      id: field.id,
      name: field.name,
      data_type: field.data_type,
      created_at: time(field.created_at),
      updated_at: time(field.updated_at),
      node_id: global_id_for(field, options),
      project_url: projects_v2_url_for_owner(project.owner, project.number, options),
    }

    if field.single_select?
      field_data[:options] = field.settings_options_objects_all.map { |settings| projects_v2_single_select_field_value_hash(settings, options) }
    end

    if field.iteration?
      configuration = field.settings.fetch("configuration", {})

      field_data[:configuration] = {
          start_day: configuration["start_day"],
          duration: configuration["duration"],
          iterations: field.settings_iterations_objects_all.map { |settings| projects_v2_iteration_field_value_hash(settings, options) }
      }
    end

    field_data
  end

  sig do
    params(
     value: T.nilable(MemexProjectColumn::Settings::Iteration),
     options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
   ).returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def projects_v2_iteration_field_value_hash(value, options = {})
    return unless value

    {
      id: value.id,
      start_date: value.start_date,
      duration: value.duration,
      title: {
        raw: value.title,
        html: value.title_html
      },
      completed: value.completed?
    }
  end

  sig do
    params(
      value: T.nilable(MemexProjectColumn::Settings::OptionEntry),
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def projects_v2_single_select_field_value_hash(value, options = {})
    return unless value

    {
      id: value.id,
      name: {
        raw: value.name,
        html: value.name_html
      },
      description: {
        raw: value.description,
        html: value.description_html
      },
      color: value.color,
    }
  end

  sig do
    params(
      item: MemexProjectItem,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[String, T.untyped])
  end
  def projects_item_hash(item, options = {})
    options = Api::SerializerOptions.from(options)

    GitHub.dogstats.time("api.serializer.projects_item_hash") do
      project = T.must(item.memex_project)
      base_path = build_project_base_path(project, options)

      result = {
        id: item.id,
        node_id: global_id_for(item, options),
        project_url: url("#{base_path}"),
        content: get_content_hash_for_item(item, options),
        content_type: item.content_type,
        creator: simple_user_hash(item.creator, content_options(options)),
        created_at: time(item.created_at),
        updated_at: time(item.updated_at),
        archived_at: time(item.archived_at),
        item_url: url("#{base_path}/items/#{item.id}"),
      }

      fields = T.cast(options[:fields] || [], T::Array[MemexProjectColumn::Field::Base])
      redacted_issue_ids = options[:redacted_issue_ids] || []

      result[:fields] = fields.map do |field|

        {
          id: field.id,
          name: field.name,
          data_type: field.data_type,
          value: field.to_rest_api_hash(item, redacted_issue_ids:)
        }
      end

      result
    end
  end

  private

  sig do
    params(
      owner: T.any(Organization, User),
      project_number: Integer,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(String))
  end
  def projects_v2_url_for_owner(owner, project_number, options = {})
    path = case owner
    when Organization
      "/orgs/#{owner.display_login}/projectsV2/#{project_number}"
    when User
      "/users/#{owner.display_login}/projectsV2/#{project_number}"
    else
      T.absurd(owner)
    end

    url(path, options)
  end

  sig do
    params(
      project: MemexProject,
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(String)
  end
  def build_project_base_path(project, options)
    owning_resource = project.owner.organization? ? "orgs" : "users"
    Api::LegacyEncode.encode("/#{owning_resource}/#{project.owner.display_login}/projectsV2/#{project.number}", /\[|\]/)
  end

  sig do
    params(
      item: MemexProjectItem,
      options: T.untyped
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def get_content_hash_for_item(item, options)
    return unless content = item.content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    case content
    when Issue
      # Explicitly load full repositories for consistent behavior with pull requests
      options[:repositories] = true
      issue_hash(content, options)
    when PullRequest
      pull_request_hash(content, options)
    when DraftIssue
      content.memex_content_hash(fields: [:title, :body, :created_at, :updated_at])
        .merge({
          node_id: global_id_for(content, options),
          user: simple_user_hash(content.creator, content_options(options))
        })
    else
      T.absurd(content)
    end
  end
end
