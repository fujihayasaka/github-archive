# typed: true
# frozen_string_literal: true

module ApplicationController::SearchIndexOverrideDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    around_action :check_search_index_override
  end

  private

  def check_search_index_override
    return yield unless params[:_search_index] && site_admin?

    GitHub.set_search_index_override(params[:_search_index])
    yield
  ensure
    GitHub.set_search_index_override(nil)
  end
end
