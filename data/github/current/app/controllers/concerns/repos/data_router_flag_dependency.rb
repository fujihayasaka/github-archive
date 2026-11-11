# typed: true
# frozen_string_literal: true

module Repos
  module DataRouterFlagDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    include GitHub::Memoizer

    requires_ancestor { AbstractRepositoryController }

    included do
      memoize def data_router_feature_flag_enabled?
        result = check_app_type_header
        return result unless result.nil?
        feature_enabled_globally_or_for_user?(feature_name: :react_data_router_code_view, subject: current_user)
      end
    end
  end
end
