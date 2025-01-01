class API::Types::BaseField < GraphQL::Schema::Field
  def initialize(*args, **kwargs, &block)
    super
    extension(GraphQLFieldTimerExtension)
  end
end
