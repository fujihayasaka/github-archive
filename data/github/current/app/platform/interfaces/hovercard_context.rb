# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module HovercardContext
      include Platform::Interfaces::Base
      description "An individual line of a hovercard"

      field :message, String, description: "A string describing this context", null: false

      def message
        if @object.respond_to?(:async_message)
          @object.async_message
        else
          @object.message
        end
      end

      field :octicon, String, description: "An octicon to accompany this context", null: false

      # Custom type resolver for types with separate definitions
      def self.resolve_type(object, context)
        case object
        when UserHovercard::Contexts::Organizations
          Objects::OrganizationsHovercardContext
        when UserHovercard::Contexts::OrganizationTeams
          Objects::OrganizationTeamsHovercardContext
        when IssueOrPullRequestHovercard::Contexts::ViewerInvolvement
          Objects::ViewerHovercardContext
        when IssueOrPullRequestHovercard::Contexts::ReviewStatus
          Objects::ReviewStatusHovercardContext
        else
          Objects::GenericHovercardContext
        end
      end
    end
  end
end
