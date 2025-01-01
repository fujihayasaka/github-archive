# typed: true
# frozen_string_literal: true

# NOTE: This controller has been DEPRECATED! Please do not add new usage of
# it. We are moving away from using internal GraphQL schema for views.

# Endpoint for internally persisted GraphQL queries.
#
# Uses cookie session authentication rather than an OAuth token. This endpoint
# should be used instead of `api.github.com/graphql` for same origin github.com
# XHR requests.
#
# All queries must be persisted and checked somewhere under the `app/assets`
# directory as a `.graphql` file.
class QueriesController < ApplicationController
  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:query]

  class Error < StandardError; end

  # This controller is a general purpose controller, not specific to domain of
  # the application.

  # XXX: This controller doesn't require any authorization checks. Data
  # loading is handled by GraphQL Platform. Conditional access checks are
  # enforced via the `enforce_conditional_access_via_graphql` context option.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  # Internal: Registry of partials.
  @@operations = {}

  # Load all *.graphql files from frontend assets directory.
  #
  # All files MUST define a unique named operation. This is how opeations will
  # be referenced.
  #
  #   query MyAwesomeQueryName { viewer { ... } }
  #
  Dir["#{Rails.root}/app/assets/**/*.graphql"].each do |path|
    next if path.include?("clientExtensions.graphql") # ignore relay local client extensions
    mod = PlatformHelper::PlatformClient.parse(File.read(path), path, 0)
    if mod.is_a?(Module)
      mod.constants.each do |constant|
        if @@operations[constant.to_s]
          raise Error, "duplicate operation name: #{constant}"
        end
        @@operations[constant.to_s] = mod.const_get(constant)
      end
    else
      raise Error, ".graphql file is missing operation name: #{path}"
    end
  end

  # GET|POST /_graphql/MyAwesomeQueryName
  def query # rubocop:todo GitHub/UseRestfulActions
    unless request.xhr?
      return render status: :forbidden, plain: "Must be requested with X-Requested-With: XMLHttpRequest"
    end

    unless operation = @@operations[params[:operation_name]]
      return render status: :not_found, plain: "Could not find operation"
    end

    operation_type = operation.definition_node.operation_type

    if !request.post? && operation_type != "query"
      return render status: :forbidden, plain: "Mutations must be requested with a POST request"
    end

    variables = {}
    if params[:variables]
      variables = params[:variables].to_unsafe_h
    end

    respond_to do |format|
      format.json do
        # TODO: Add GraphQL::Client::Response#to_h to access unmodified original hash
        # For now, use PlatformExecute#execute directly to get to raw response.
        response = PlatformExecute.execute(
          document: operation.document,
          operation_name: operation.definition_node.name,
          variables: variables,
          request_env: request.env,
          context: platform_context.merge(query_name: params[:operation_name],
                                          user_session: user_session,
                                          track_query_name: true,
                                          enforce_conditional_access_via_graphql: true))

        render json: add_performance_trace(
          response,
          params[:operation_name],
          operation.document.to_query_string,
          variables
        )
      end
    end
  end

  private

  def add_performance_trace(result, query_name, query_text, variables)
    return result unless tracing_enabled?

    tracer = Platform::GlobalScope.tracers&.find { |t| t.is_a?(Platform::PerformancePaneTracer) }

    if tracer
      extensions_result = Platform::PerformancePaneTracer::ExtensionsResult.new(tracer)
      result[:trace] = extensions_result.to_h
      result[:trace][:query_name] = query_name
      result[:trace][:query_text] = query_text
      result[:trace][:query_variables] = variables
      result[:trace][:method] = request.method
      result[:trace][:url] = request.url
    end

    JSON.generate(result.to_h)
  end

  def tracing_enabled?
    stats_ui_enabled? && params["graphql_query_trace"].presence == "true"
  end
end
