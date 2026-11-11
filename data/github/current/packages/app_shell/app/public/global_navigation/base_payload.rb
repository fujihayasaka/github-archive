# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class BasePayload < ReactPayload::Base
    include ApplicationHelper
    include GitHub::Memoizer
    include GitHub::ResilienceMixin
    include UrlHelpers
    include KeyboardShortcutsHelper
    include CopilotChatHelper

    abstract!

    sig { override.returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(T.nilable(Repository)) }
    attr_reader :current_repository

    sig { returns(T.nilable(Organization)) }
    attr_reader :current_organization

    sig { returns(String) }
    attr_reader :source

    sig do
      params(
        source: String,
        current_user: T.nilable(User),
        current_copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User)),
        current_repository: T.nilable(Repository),
        current_organization: T.nilable(Organization)
      ).void
    end
    def initialize(
      source:,
      current_user:,
      current_copilot_user: nil,
      current_repository: nil,
      current_organization: nil
    )
      @current_user = current_user
      @current_copilot_user = T.let(current_copilot_user, T.nilable(T.any(Copilot::User, Copilot::Public::User)))
      @current_repository = current_repository
      @current_organization = current_organization
      @source = source
    end

    sig { returns(T::Array[String]) }
    memoize def tracking_tags
      ["source:#{source}"]
    end

    sig { override.returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
    memoize def current_copilot_user_v2
      return @current_copilot_user if @current_copilot_user
      return nil unless current_user

      with_database_error_fallback(fallback: nil) do
        Copilot::Public::User.new(T.must(current_user))
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def issues_payload
      GitHub.dogstats.time("global_navigation.issues", tags: tracking_tags) do
        { href: all_issues_path }
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def pulls_payload
      GitHub.dogstats.time("global_navigation.pulls", tags: tracking_tags) do
        { href: all_pulls_path }
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def contributed_repos_payload
      GitHub.dogstats.time("global_navigation.contributed_repos", tags: tracking_tags) do
        {
          show: repos_contributed_page_enabled?,
          href: repos_contributed_page_enabled? ? repositories_finder_path : nil,
        }
      end
    end

    sig { returns(T::Boolean) }
    def logged_in?
      current_user.present?
    end

    sig { returns(T::Boolean) }
    def copilot_enabled?
      with_database_error_fallback(fallback: false) { show_copilot_chat_entrypoint? }
    end

    sig { returns(T::Boolean) }
    def spark_enabled?
      with_database_error_fallback(fallback: false) { show_spark_entrypoint? }
    end

    private

    sig { returns(T.nilable(T::Boolean)) }
    memoize def repos_contributed_page_enabled?
      !GitHub.enterprise? && FeatureFlag.vexi.enabled?(:repos_relevance_page, current_user, default: false)
    end
  end
end
