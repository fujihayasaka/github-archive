# typed: false
# frozen_string_literal: true

# NOTE: This controller has been DEPRECATED! Please do not add new partials to
# it. We are moving away from using internal GraphQL schema for views.

# This was extracted from a generic NodesController. Since using GraphQL schema
# for views is no longer supported, this legacy controller has been created to
# support the legacy projects path. This controller is owned by the Projects
# service and should be deprecated when legacy projects are deprecated.

#
# ProjectNodesController#show exposes a single projects-specific endpoint
# clients can access to re-render parts of the page in response to live updates.
#
#   GET /_render_node/MDU6SXNzdWUzNDEy/projects/header
#
# Prefer using the `show_project_node_partial_path` URL helper to generate this path.
#
#   show_project_node_partial_path(path: "projects/header", id: project.owner.id)
#
# In order to use this endpoint, partials MUST fetch all their data from GraphQL
# and define their dependencies via an ERB GraphQL query.
class ProjectNodesController < ApplicationController
  # This controller is a general purpose controller for projects based nodes.
  # Most of these partials are used by live updates.

  # XXX: This controller doesn't require any authorization checks. Data
  # loading is handled by GraphQL Platform. Conditional access is enforced via the
  # `enforce_conditional_access_via_graphql` context option.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Memex,
    only: [:show]

  # Internal: Registry of partials.
  @@partials = {}
  cattr_reader :partials

  # Internal: Container to register static show action queries.
  module Queries
  end

  module Fragments
  end

  # Public: Expose partial via #show action.
  #
  # partial - String render path of partial.
  #           Just "projects/header", not "app/views/projects/_header.html.erb".
  #
  # fragment - GraphQL::Client fragment to fetch data for. Assumes the first
  #            fragment defined by the partial by default.
  #
  # local_assign - Symbol local name the data should be assigned to in the
  #                partial. Assumes a downcased name of the fragment.
  #
  # Returns nothing.
  def self.route_partial(partial, fragment: nil, local_assign: nil, variables: {})
    unless fragment
      namespace = "views/#{partial}".camelize.constantize
      fragment_name = namespace.constants.sort.first
      if fragment_name.nil?
        fragment = namespace
      else
        fragment = namespace.const_get(fragment_name)
      end
    end

    # comment
    local_assign ||= fragment.name.split("::").last.underscore

    if fragment.definition_node.type.name == "Query"
      # query { ...Views::Dashboard::Index::Data }
      query = PlatformHelper::PlatformClient.create_operation(fragment)
      type = :query
    else
      # query($id: ID!) { node(id: $id) { ...Views::Comments::Show::Comment } }
      node_fragment_const_name = partial.camelize.gsub("::", "") + "Fragment"
      node_fragment = Fragments.const_set(
        node_fragment_const_name,
        # rubocop:todo GitHub/DoNotCallParseQuery
        parse_query("fragment on Query { node(id: $id) { ...#{fragment.name} } }"),
        # rubocop:enable GitHub/DoNotCallParseQuery
      )

      query = PlatformHelper::PlatformClient.create_operation(node_fragment)
      type = :node
    end

    query_const_name = partial.camelize.gsub("::", "")
    Queries.const_set(query_const_name, query)

    schema_klass = PlatformTypes.const_get(fragment.definition_node.type.name)

    @@partials[partial] = {
      type: type,
      path: partial,
      local_assign: local_assign.to_sym,
      node_fragment: node_fragment,
      fragment: fragment,
      schema_klass: schema_klass,
      query: query,
      variables: variables,
    }
  end

  # Only allow id and path params. Views MUST NOT depend on any additional
  # URL parameters in order to use this actions.
  ALLOWED_PARAM_KEYS = %i(controller action id path variables utf8 _features legacy)

  # GET /_render_node/MDU6SXNzdWUzNDEy/projects/header
  def show

    # Check if partial is registered, otherwise 404
    unless partial = @@partials[node_params[:path]]
      return head :not_found
    end

    locals = {}

    variables = node_params[:variables]&.to_h || {}
    variables.reverse_merge!(partial[:variables])

    # This is a hack to allow the metadata pane to conditionally
    # remove the project clone option. Because we cannot fetch this readily in an ERB GraphQL query,
    # allow this to pass this value a local variable to the template.
    if variables.key?(:show_deprecation_announcement)
      locals[:show_deprecation_announcement] = ActiveRecord::Type::Boolean.new.deserialize(variables[:show_deprecation_announcement])
      variables.delete(:show_deprecation_announcement)
    end

    if partial[:type] == :node
      variables[:id] = node_params[:id]
    end

    type_cast_variables!(variables, partial[:query].definition_node.variables)
    params[:variables] = variables

    begin
      data = platform_execute(partial[:query], variables: variables, context: { enforce_conditional_access_via_graphql: true, unfurl_references: true })
    rescue PlatformHelper::ConditionalAccessError => e
      # this is an xhr request, so follow the pattern in
      # https://github.com/github/github/blob/4bf41fdfcdc9b7b30615e5dc7df6ae55bf73c583/app/controllers/application_controller/external_sessions_dependency.rb#L186-L187
      return head :unauthorized
    rescue PlatformHelper::ExecutionError => e
      if e.message =~ /\AVariable.*was provided invalid value\Z/
        return head :bad_request
      else
        raise
      end
    end

    locals[:variables] = variables

    if node_params[:id] == "query"
      locals[partial[:local_assign]] = data
    else
      data = partial[:node_fragment].new(data)

      unless data.node
        return head :not_found
      end

      # Detect if node was found but was unexpected type.
      unless data.node.is_a?(partial[:schema_klass])
        return head :not_found
      end

      locals[partial[:local_assign]] = data.node
    end

    respond_to do |format|
      GitHub.dogstats.increment "nodes.show", tags: %W(type:#{partial[:schema_klass].type.graphql_name.underscore} partial:#{partial[:path]})
      format.html_fragment do
        render partial: partial[:path], formats: [:html], locals: locals # rubocop:disable GitHub/RailsControllerRenderLiteral
      end
      format.html do
        render partial: partial[:path], locals: locals # rubocop:disable GitHub/RailsControllerRenderLiteral
      end
    end
  end

  # Routed Partials
  #
  # These partials are exposed via the #show action.
  #
  # Keep list sorted alphabetically.
  #
  # DEPRECATED! PLEASE DO NOT ADD TO THIS LIST
  route_partial "projects/fullscreen_header"
  route_partial "projects/header"
  route_partial "projects/panes/metadata"
  route_partial "projects/show_progress"
  # DEPRECATED! PLEASE DO NOT ADD TO THIS LIST

  private

  # Internal: Type casts param variables to the specified type of the query variable
  #
  # - params_variables     - Hash of param variables
  # - variable_definitions - Array of `GraphQL::Language::Nodes::VariableDefinition`s
  #
  # Returns nothing
  def type_cast_variables!(params_variables, variable_definitions)
    variable_definitions.each do |variable|
      base_type = variable.type
      if base_type.is_a? GraphQL::Language::Nodes::NonNullType
        base_type = base_type.of_type
      end
      next unless base_type.respond_to?(:name)
      next unless value = params_variables[variable.name]

      casted_value =
        case base_type.name
        when "Boolean"
          ActiveRecord::Type::Boolean.new.deserialize(value)
        when "Int"
          ActiveRecord::Type::Integer.new.deserialize(value)
        end

      params_variables[variable.name] = casted_value unless casted_value.nil?
    end
  end

  memoize def node_params
    # Since we raise on unallowed keys, we want to drop them
    # here first and only add allowed ones.
    filtered = params.class.new
    ALLOWED_PARAM_KEYS.each do |key|
      val = params[key]
      val.permit! if val.respond_to?(:permit!)
      filtered[key] = val
    end

    filtered.permit!
    filtered
  end

  memoize def current_repository
    owner.find_repo_by_name(params[:repository]) if owner && params[:repository]
  end

  memoize def owner
    User.find_by_login(params[:user_id]) if params[:user_id]
  end
end
