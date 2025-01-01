# typed: true
# frozen_string_literal: true

module Api::App::RepositoryAdvisoriesHelpers
  extend T::Helpers
  requires_ancestor { Api::App }

  def deliver_advisories(advisories)
    options = T.let({
      current_user: current_user,
      last_modified: calc_last_modified(advisories),
    }, T::Hash[Symbol, T.untyped])

    deliver :repository_advisories_hash, { advisories: advisories }, options
  end

  def ensure_non_conflicting_cursor_params!
    if params.key?(:after) && params.key?(:before)
      deliver_error!(400, message: "Please do not provide both 'before' and 'after' parameters.")
    end
  end

  def order_advisories(advisories)
    order_by = :"#{params[:sort] || "created"}_#{params[:direction] || "desc"}"
    case order_by
    when :created_asc
      advisories.order(id: :asc)
    when :created_desc
      advisories.order(id: :desc)
    when :updated_asc
      advisories.order(updated_at: :asc)
    when :updated_desc
      advisories.order(updated_at: :desc)
    when :published_asc
      advisories.order(published_at: :asc)
    when :published_desc
      advisories.order(published_at: :desc)
    else
      advisories.order(id: :desc)
    end
  end
end
