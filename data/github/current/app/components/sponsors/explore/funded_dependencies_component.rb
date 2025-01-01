# typed: true
# frozen_string_literal: true

class Sponsors::Explore::FundedDependenciesComponent < ApplicationComponent
  # direct_only - Boolean indicating whether only direct dependencies are represented on the page
  # org - Organization whose dependencies were checked
  def initialize(direct_only:, org:)
    @direct_only = !!direct_only
    @org = org
  end

  private

  attr_reader :org

  def render?
    @direct_only &&
      GitHub.sponsors_enabled? &&
      logged_in? &&
      org&.organization? &&
      total_direct_dependencies_sponsorable.positive?
  end

  memoize def total_direct_dependencies_sponsored
    org.total_direct_dependencies_sponsored(viewer: current_user)
  end

  memoize def total_direct_dependencies_sponsorable
    org.total_direct_dependencies_sponsorable(viewer: current_user)
  end

  def percentage
    pct = (total_direct_dependencies_sponsored.to_f / total_direct_dependencies_sponsorable) * 100
    pct.round
  end
end
