# typed: strict
# frozen_string_literal: true

module Sponsors::SharedDependenciesControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  DEPENDENCIES_PER_PAGE = 8

  included do

    T.bind(self, T.class_of(ApplicationController))

    sig { void }
    def require_allowed_filter_org_if_given
      # No org was specified so the current viewer will be used:
      return if params[:account].blank? || logged_in? && params[:account] == current_user.login

      head(:forbidden) unless filter_org
    end

    sig { returns T::Boolean }
    memoize def direct_dependencies_only?
      params[:direct] != "0"
    end

    sig { void }
    def require_supported_ecosystem
      return if ecosystem_filters.empty?

      supported_ecosystems = Platform::Enums::DependencyGraphEcosystem.values.keys.to_set
      unsupported_ecosystem_filters = ecosystem_filters.to_set - supported_ecosystems
      return if unsupported_ecosystem_filters.empty?

      return head(:bad_request) if pjax? || request.xhr?

      units = "ecosystem".pluralize(unsupported_ecosystem_filters.size)
      flash[:error] = "Sorry, we don't support the #{unsupported_ecosystem_filters.to_a.to_sentence} #{units}."

      valid_ecosystems = (ecosystem_filters.to_set - unsupported_ecosystem_filters).to_a
      valid_ecosystems = nil if valid_ecosystems.empty?

      redirect_to sponsors_explore_index_path(
        account: params[:account],
        sort_by: params[:sort_by],
        ecosystems: valid_ecosystems,
      )
    end

    sig { returns T::Array[String] }
    memoize def ecosystem_filters
      SponsorsExploreFilterSet.ecosystems_from(params)
    end

    # Private: The requested org whose dependencies should be viewed, if one was requested. For org admin viewers,
    # the org's private and public repositories will be checked for dependencies. For all other viewers, only the
    # org's repositories that are visible to that viewer will be checked for dependencies.
    sig { returns T.nilable(Organization) }
    memoize def filter_org
      if logged_in? && params[:account] != current_user.login
        with_database_error_fallback do
          org = Organization.find_by(login: params[:account])
          org if current_user.can_load_sponsorable_dependencies_for?(org)
        end
      end
    end

    sig { returns SponsorsExploreFilterSet }
    memoize def filter_set
      return SponsorsExploreFilterSet.new unless logged_in?
      SponsorsExploreFilterSet.new(
        page: current_page,
        per_page: DEPENDENCIES_PER_PAGE,
        sort_by: params[:sort_by],
        ecosystems: ecosystem_filters,
        direct_only: direct_dependencies_only?,
        account_login: filter_org&.login,
      )
    end

    sig { returns T.any(Organization, User, Symbol) }
    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      return T.must(filter_org) if filter_org
      current_user
    end
  end
end
