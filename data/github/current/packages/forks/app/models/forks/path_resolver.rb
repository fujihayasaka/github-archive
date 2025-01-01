# typed: true
# frozen_string_literal: true

class Forks::PathResolver
  # This class turns URL query parameters into a more usable object for
  # manipulating those paramters for hrefs to desired states set by the user.
  # The controller creates this; the forks/controls components use this to
  # build branched hrefs from the current state. Those branched hrefs are received
  # by the controller to pass it into the next request.
  extend T::Sig

  sig { returns(String) }
  attr_reader :repo_name, :repo_owner_display_login

  sig { returns(Forks::SearchOptionsResolver) }
  attr_reader :options

  sig { params(repo_name: String, repo_owner_display_login: String, options_resolver: Forks::SearchOptionsResolver).void }
  def initialize(repo_name, repo_owner_display_login, options_resolver)
    @options = options_resolver
    @repo_name = repo_name
    @repo_owner_display_login = repo_owner_display_login
  end

  sig { params(overrides: T::Hash[Symbol, T.untyped]).returns(Forks::PathResolver) }
  def copy(overrides = {})
    self.class.new(
      @repo_name,
      @repo_owner_display_login,
      @options.copy(overrides)
    )
  end

  def to_path
    url_helpers.forks_url(
      repo_owner_display_login,
      repo_name,
      only_path: true,
      **@options.to_query_args
    )
  end

  def next_path(**overrides)
    self.copy(**overrides).to_path
  end

  private

  def url_helpers
    Rails.application.routes.url_helpers
  end
end
