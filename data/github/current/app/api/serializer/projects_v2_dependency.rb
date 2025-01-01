# typed: false
# frozen_string_literal: true

module Api::Serializer::ProjectsV2Dependency
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

  def projects_v2_status_update_hash(status_update, options = {})
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
end
