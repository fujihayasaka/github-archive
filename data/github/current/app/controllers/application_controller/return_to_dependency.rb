# typed: strict
# frozen_string_literal: true

module ApplicationController::ReturnToDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :return_to
  end

  sig { void }
  def set_return_to
    if params[:return_to] == "gist"
      session[:return_to] = GitHub.gist_url
    elsif params[:return_to].present?
      session[:return_to] = params[:return_to]
    end
  end

  # Redirect to the URI stored by the most recent store_location call or
  # to the passed default. Also clears the return_to value from the session.
  sig { params(fallback: T.nilable(String)).void }
  def redirect_to_return_to(fallback: nil)
    safe_redirect_to(
      return_to,
      fallback: fallback ||= request.env["return_to"],
      allow_query: true,
      allow_fragment: true,
      allow_hosts: safe_redirect_hosts,
    )
  end

  # Merge given parameters in to stored `return_to`, rewriting the value stored on the session.
  sig { params(merge_params: T::Hash[Symbol, T.any(String, Symbol, T::Boolean)]).void }
  def merge_return_to_params(merge_params)
    return unless return_to.present?

    returning_to = URI.parse(T.cast(return_to, String))
    query = Rack::Utils.parse_query(returning_to.query)
    returning_to.query = query.merge(merge_params).to_param

    session[:return_to] = returning_to.to_s
    @return_to = T.let(session[:return_to], T.nilable(String))
  rescue URI::InvalidURIError => e
    Failbot.report(e)
  end

  # Memoizes the return_to param, clearing it from the session cookie if it exists
  sig { returns(T.nilable(String)) }
  def return_to
    @return_to ||= T.let(session.delete(:return_to) || request.env["return_to"] || params[:return_to], T.nilable(String))
  end

  sig { returns(T::Array[String]) }
  def safe_redirect_hosts
    [
      GitHub.urls.host_name,
      GitHub.urls.raw_host_name,
      GitHub.pages_host_name_v2,
      GitHub.pages_auth_host_name,
      GitHub.gist_host_name,
      GitHub.gist3_host_name,
      GitHub.urls.codeload_host_name,
      Notebook.host_url,
      Viewscreen.host_url,
      GitHub.classroom_host,
    ].uniq.compact
  end
end
