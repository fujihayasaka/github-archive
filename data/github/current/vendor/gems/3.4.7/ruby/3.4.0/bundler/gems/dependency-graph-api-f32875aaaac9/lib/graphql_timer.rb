module GraphQLTimer
  module_function

  def before_query(query)
    payload = { query: query }
    ActiveSupport::Notifications.instrument("graphql.query.started", payload)

    query.context[:start_time] = Time.current
  end

  def after_query(query)
    payload = { query: query }
    ActiveSupport::Notifications.instrument("graphql.query.finished", payload)

    if query.context[:start_time]
      payload[:duration] = Time.current - query.context[:start_time]
      ActiveSupport::Notifications.instrument("graphql.query.time", payload)
    end
  end
end

class GraphQLFieldTimerExtension < GraphQL::Schema::FieldExtension
  def resolve(object:, arguments:, **rest)
    # yield the current time as `memo`
    yield(object, arguments, Time.current)
  end

  def after_resolve(value:, memo:, **rest)
    duration = Time.current - memo
    payload = { type: value.class, field: field, duration: duration }
    ActiveSupport::Notifications.instrument("graphql.field.time", payload)

    # Return the original value
    value
  end
end
