# typed: true
# frozen_string_literal: true

class Forks::ScopeResolver
  # Resolves scoped attributes for the forks/_index view,
  # with the intent to handle all database logic in one place,
  # so that we can appropriately optimize our sorting and querying
  # operations.

  include GitHub::Memoizer

  RESULT_LIMIT = GitHub.max_ui_pagination_page * ApplicationController::DEFAULT_PER_PAGE

  sig { params(root_repository: Repository, current_user: T.nilable(User), include: T::Array[Symbol],  period: String, result_limit: Integer).void }
  def initialize(root_repository, current_user:, include:, period:, result_limit: RESULT_LIMIT)
    @root_repository = root_repository
    @current_user = current_user
    @include = include
    @period = time_shorthand_to_timestamp(period)
    @result_limit = result_limit
  end

  def resolve
    apply_period
    apply_repository_types
    apply_scope_limit
  end

  memoize def base_scope
    scope = if :network.in?(@include)
      Repository
        .active
        .in_same_network_as(@root_repository)
        .where.not(id: @root_repository.id)
    else
      Repository.forks_of(@root_repository)
    end

    scope.filter_spam_and_disabled_for(@current_user)
  end

  private

  def chained_scope
    @chained_scope ||= base_scope
  end

  def apply_period
    return @chained_scope if @period.blank?
    @chained_scope = chained_scope.where("pushed_at > ?", @period)
  end

  def apply_repository_types
    @chained_scope = chained_scope.not_archived_scope unless :archived.in? @include
    @chained_scope = chained_scope.where("#{Repository.stargazer_count_column} > 0") if :starred.in? @include

    # We only really care if one or the other is here; if
    # both are, we don't need to apply any additional scoping.
    if :active.in?(@include) && !:inactive.in?(@include)
      @chained_scope = chained_scope.where("pushed_at > created_at")
    elsif :inactive.in?(@include) && !:active.in?(@include)
      @chained_scope = chained_scope.where("pushed_at <= created_at")
    end
  end

  def apply_scope_limit
    @chained_scope = chained_scope.limit(@result_limit)
  end

  sig { params(time_shorthand: String).returns(T.nilable(Time)) }
  def time_shorthand_to_timestamp(time_shorthand)
    return nil unless match = time_shorthand.match(/(\d+)(y|mo|w|d)/)

    span = match.captures.first.to_i
    scale = match.captures.last

    scale_time_span = case scale
    when "y"
      span.years
    when "mo"
      span.months
    when "w"
      span.weeks
    when "d"
      span.days
    end

    # This already is a Time instance, but for some reason
    # Sorbet can't figure this one out.
    T.cast(Time.now - scale_time_span, Time)
  end
end
