# typed: true
# frozen_string_literal: true
module Organizations
  class Teams::ReviewAssignmentComponent < ApplicationComponent
    attr_reader :team

    def initialize(team:)
      @team = team
    end

    def org
      team.organization
    end

    def team_slug
      team.slug
    end

    def review_assignment_toggler_test_selector
      team.review_request_delegation_enabled? ? "review-assignment-toggler-on" : "review-assignment-toggler"
    end

    def review_assignment_toggler_class_names
      review_assignment_classes = "js-toggler-container review_assignment_toggler"
      return review_assignment_classes if !team.review_request_delegation_enabled?
      "#{review_assignment_classes} on"
    end
  end
end
