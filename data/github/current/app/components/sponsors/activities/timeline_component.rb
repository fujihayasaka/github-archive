# typed: true
# frozen_string_literal: true

class Sponsors::Activities::TimelineComponent < ApplicationComponent
  # activities - an ordered ActiveRecord::Relation or Array of SponsorsActivity
  # activities_path - String URL for loading other pages of activity
  sig do
    params(
      activities: T.any(T::Array[SponsorsActivity], ActiveRecord::Relation),
      activities_path: T.nilable(String),
      page: Integer,
      per_page: Integer,
    ).void
  end
  def initialize(activities:, activities_path:, page: 1, per_page: Sponsors::ActivitiesController::PER_PAGE)
    @activities_path = activities_path
    @page = page
    @per_page = per_page
    @activities = activities
    @total_pages = 1
  end

  private

  attr_reader :activities_path

  sig { returns T::Array[SponsorsActivity] }
  memoize def paginated_activities
    result = @activities.paginate(page: @page, per_page: @per_page)
    @total_pages = result.total_pages
    SponsorsActivity.preload_for_activity_component(result)
    result.to_a
  end

  sig { returns T::Boolean }
  def has_next_page?
    @total_pages > @page
  end

  sig { returns T.nilable(SponsorsActivity) }
  memoize def first_activity
    paginated_activities.first if @page == 1
  end

  sig { returns T.nilable(SponsorsActivity) }
  memoize def last_activity
    paginated_activities.last unless has_next_page?
  end
end
