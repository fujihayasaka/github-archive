# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Members
      class ManualCriterionView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

        # Some criterion may require us to display additional information
        # under the criterion to help make our decision. For those criterion,
        # you should add the slug to this array and add an associated partial in
        # `app/views/stafftools/sponsors/members/criteria`.
        CUSTOM_PARTIALS = %w[
          objectionable_content
          member_reputable_org
          fiscal_host_member
        ]

        attr_reader :check

        # Public: The slug of the criterion for this health check.
        #
        # Returns a String.
        def slug
          check.sponsors_criterion.slug
        end

        # Public: The global relay ID for this criterion.
        #
        # Returns a String.
        def id
          check.id
        end

        # Public: Indicates if the health check criterion is met.
        #
        # Returns a Boolean.
        def met?
          check.met?
        end

        # Public: The text describing the criterion being evaluated.
        #
        # Returns a String.
        def description
          check.sponsors_criterion.description
        end

        # Public: Does this criterion have a custom partial to display with it?
        #
        # Returns a Boolean.
        def has_partial?
          CUSTOM_PARTIALS.include?(slug)
        end

        # Public: The path to the partial for this criterion.
        #
        # Returns a String|nil.
        def partial_path
          return unless has_partial?
          "stafftools/sponsors/members/criteria/#{slug}"
        end
      end
    end
  end
end
