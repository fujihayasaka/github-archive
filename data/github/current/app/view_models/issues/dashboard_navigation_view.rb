# typed: true
# frozen_string_literal: true

module Issues
  class DashboardNavigationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :query

    def selected_link
      if query =~ /assignee:/
        :dashboard_assigned
      elsif query =~ /author:/
        :dashboard_created
      elsif query =~ /mentions:/
        :dashboard_mentioned
      elsif query =~ /review-requested:/
        :dashboard_review_requested
      end
    end
  end
end
