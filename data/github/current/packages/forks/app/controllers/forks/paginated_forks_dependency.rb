# typed: true
# frozen_string_literal: true

module Forks::PaginatedForksDependency
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Forks::ForksController }

  sig { params(repository: Repository, actor: T.nilable(User), options: Forks::SearchOptionsResolver).returns(ActiveRecord::Relation) }
  def paginated_forks_for(repository:, actor:, options:)
    scope_resolver = Forks::ScopeResolver.new(
      repository,
      current_user: actor,
      include: options.include,
      period: options.period
    )

    query_is_valid = (options.include & [:active, :inactive]).any?

    scope = query_is_valid ? scope_resolver.resolve : Repository.none
    @base_scope = scope_resolver.base_scope
    @attribute_resolver = Forks::AttributeResolver.new(scope)

    return scope unless query_is_valid

    sorted_scope(
      options.sort_by,
      @attribute_resolver
    ).paginate(
      page: options.page,
      per_page: ApplicationController::DEFAULT_PER_PAGE
    )
  end

  sig { params(sort_by: Symbol, attribute_resolver: Forks::AttributeResolver).returns(ActiveRecord::Relation) }
  def sorted_scope(sort_by, attribute_resolver)
    scoped_ids = attribute_resolver.ids_by_owner_login
    sorted_ids = attribute_resolver.resolve[sort_by].keys
    zero_count_ids = scoped_ids - sorted_ids
    Repository.in_order_of(:id, sorted_ids + zero_count_ids)
  end
end
