# typed: false
# frozen_string_literal: true

module Api::Serializer::ProjectsDependency
  ProjectFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Project {
      id
      databaseId
      name
      owner {
        ... on Repository {
          name
          owner {
            login
          }
        }
        ... on Organization {
          login
        }
        ... on User {
          login
        }
      }
      body
      number
      state
      url
      creator {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
      createdAt
      updatedAt

      organizationPermission
      isPublic
    }
  GRAPHQL

  def graphql_project_hash(project, options = {})
    options = Api::SerializerOptions.from(options)
    project = ProjectFragment.new(project)
    creator = if project.creator.present?
      graphql_simple_user_hash(project.creator, content_options(options))
    else
      simple_user_hash(User.ghost, content_options(options))
    end

    hash = {
      owner_url:   project_owner_url(project.owner, options),
      url:         project_url(project.database_id),
      html_url:    project.url.to_s,
      columns_url: project_columns_url(project.database_id),
      id:          project.database_id,
      node_id:     project.id,
      name:        project.name,
      body:        project.body,
      number:      project.number,
      state:       project.state.downcase,
      creator:     creator,
      created_at:  time(project.created_at),
      updated_at:  time(project.updated_at),
    }

    if project.owner.is_a?(Api::App::PlatformTypes::Organization)
      hash[:organization_permission] = project.organization_permission.downcase
      hash[:private] = !project.is_public?
    end

    hash
  end

  # TODO: Remove this once we can figure out how to DRY up between this and
  # graphql_project_hash
  # Currently only used by Hook::Payload::ProjectPayload
  def project_hash(project, options = {})
    project_owner_identifier = case project.owner_type
    when "Repository"
      project.owner.name_with_owner_for_api(use: options[:serialize_login])
    when "Organization", "User"
      project.owner.login_for_api(use: options[:serialize_login])
    else
      raise "Invalid project owner_type: #{project.owner_type.inspect}"
    end
    options = Api::SerializerOptions.from(options)

    hash = {
      owner_url:   project_owner_url(project.owner, options),
      url:         project_url(project.id),
      html_url:    html_url("/#{project_owner_identifier}/projects/#{project.number}"),
      columns_url: project_columns_url(project.id),
      id:          project.id,
      node_id:     global_id_for(project, options),
      name:        project.name,
      body:        project.body,
      number:      project.number,
      state:       project.state,
      creator:     user_hash(project.creator, content_options(options)),
      created_at:  time(project.created_at),
      updated_at:  time(project.updated_at),
    }

    hash
  end

  ProjectColumnFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on ProjectColumn {
      id
      databaseId
      name
      project {
        ... on Project {
          databaseId
          number
          owner {
            ... on Repository {
              name
              owner {
                login
              }
            }
          }
        }
      }
      createdAt
      updatedAt
    }
  GRAPHQL

  def graphql_project_column_hash(column, options = {})
    column = ProjectColumnFragment.new(column)

    {
      url: project_column_url(column.database_id),
      project_url: project_url(column.project.database_id),
      cards_url:   project_cards_url(column.database_id),
      id:          column.database_id,
      node_id:     column.id,
      name:        column.name,
      created_at:  time(column.created_at),
      updated_at:  time(column.updated_at),
    }
  end

  # TODO: Remove this once we can figure out how to DRY up between this and
  # graphql_project_column_hash
  def project_column_hash(column, options = {})
    has_after_id = options.has_key?(:after_id)
    options = Api::SerializerOptions.from(options)
    hash = {
      url: project_column_url(column.id),
      project_url: project_url(column.project_id),
      cards_url:   project_cards_url(column.id),
      id:          column.id,
      node_id:     global_id_for(column, options),
      name:        column.name,
      created_at:  time(column.created_at),
      updated_at:  time(column.updated_at),
    }

    if has_after_id
      hash[:after_id] = options.after_id
    end

    hash
  end

  ProjectColumnCardFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on ProjectCard {
      id
      databaseId
      note
      content {
        ... on Issue {
          number
          repository {
            name
            owner {
              login
            }
          }
        }
        ... on PullRequest {
          number
          repository {
            name
            owner {
              login
            }
          }
        }
      }
      creator {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
      createdAt
      updatedAt
      column {
        databaseId
      }
      project {
        databaseId
      }
      isArchived
    }
  GRAPHQL

  def graphql_project_card_hash(card, options = {})
    options = Api::SerializerOptions.from(options)
    card = ProjectColumnCardFragment.new(card)
    creator = if card.creator.present?
      graphql_simple_user_hash(card.creator, content_options(options))
    else
      simple_user_hash(User.ghost, content_options(options))
    end

    hash = {
      url:        project_card_url(card.database_id),
      project_url: project_url(card.project.database_id),
      id:         card.database_id,
      node_id:    card.id,
      note:       card.note,
      archived:   card.is_archived?,
      creator:    creator,
      created_at: time(card.created_at),
      updated_at: time(card.updated_at),
    }

    hash[:column_url] = if card.column
      project_column_url(card.column.database_id)
    else
      project_pending_url(card.project.database_id)
    end

    if card.content
      hash[:content_url] = card_content_url(card.content, options)
    end

    hash
  end

  # TODO: Remove this once we can figure out how to DRY up between this and
  # graphql_project_card_hash
  def project_card_hash(card, options = {})
    has_after_id = options.has_key?(:after_id)
    options = Api::SerializerOptions.from(options)
    hash = {
      url: project_card_url(card.id),
      project_url: project_url(card.project_id),
      column_url: project_column_url(card.column_id),
      column_id:  card.column_id,
      id:         card.id,
      node_id:    global_id_for(card, options),
      note:       card.note,
      archived:   card.archived?,
      creator:    user_hash(card.creator, content_options(options)),
      created_at: time(card.created_at),
      updated_at: time(card.updated_at),
    }

    if card.content&.repository
      hash[:content_url] = card_content_url(card.content, options)
    end

    if has_after_id
      hash[:after_id] = options.after_id
    end

    hash
  end

  def graphql_user_project_permission_hash(permission, options = {})
    options = Api::SerializerOptions.from(options)

    {
      permission: permission.downcase,
      user: graphql_simple_user_hash(options[:user], content_options(options)),
    }
  end

  TeamProjectEdgeFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on TeamProjectEdge {
      permission
      node {
        ...Api::Serializer::ProjectsDependency::ProjectFragment
      }
    }
  GRAPHQL

  def graphql_team_project_hash(team_project_edge, options = {})
    team_project_edge = TeamProjectEdgeFragment.new(team_project_edge)
    project = team_project_edge.node

    hash = graphql_project_hash(project, content_options(options))
    return if hash.nil?

    hash[:permissions] = {
      read: %w(READ WRITE ADMIN).include?(team_project_edge.permission),
      write: %w(WRITE ADMIN).include?(team_project_edge.permission),
      admin: %w(ADMIN).include?(team_project_edge.permission),
    }

    hash
  end

  private

  def login_for_api(target, options)
    if target.is_a?(ActiveRecord::Base)
      # It's an ActiveRecord model
      target.login_for_api(use: options[:serialize_login])
    else
      # It's a GraphQL object
      # Hash is used specifically for GraphQL and login in GraphQL already return display login
      target.login # rubocop:disable GitHub/DoNotAllowLogin
    end
  end

  def card_content_url(card_content, options)
    issue_number  = card_content.number
    repository    = card_content.repository
    repo_owner    = login_for_api(repository.owner, options)
    repo_name     = repository.name
    url("/repos/#{repo_owner}/#{repo_name}/issues/#{issue_number}")
  end

  def project_url(project_id)
    url("/projects/#{project_id}")
  end

  def project_owner_url(project_owner, options)
    project_owner_type = if project_owner.is_a?(ActiveRecord::Base)
      # It's an ActiveRecord model
      project_owner.class.name
    else
      # It's a GraphQL object
      project_owner.class.type.graphql_name
    end

    path = case project_owner_type
    when "Repository"
      repo_owner_login = login_for_api(project_owner.owner, options)
      repo_name = project_owner.name

      "/repos/#{repo_owner_login}/#{repo_name}"
    when "Organization"
      "/orgs/#{login_for_api(project_owner, options)}"
    when "User"
      "/users/#{login_for_api(project_owner, options)}"
    else
      raise "Invalid project owner type: #{project_owner_type.inspect}"
    end

    url(path)
  end

  def project_pending_url(project_id)
    url("/projects/#{project_id}/cards?column=pending")
  end

  def project_columns_url(project_id)
    url("/projects/#{project_id}/columns")
  end

  def project_column_url(column_id)
    url("/projects/columns/#{column_id}")
  end

  def project_cards_url(column_id)
    url("/projects/columns/#{column_id}/cards")
  end

  def project_card_url(card_id)
    url("/projects/columns/cards/#{card_id}")
  end

  def project_all_cards_url(project_id)
    url("/projects/#{project_id}/cards")
  end
end
