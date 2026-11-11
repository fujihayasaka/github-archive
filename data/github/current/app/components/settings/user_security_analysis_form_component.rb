# typed: strict
# frozen_string_literal: true

module Settings
  class UserSecurityAnalysisFormComponent < ApplicationComponent

    sig { returns(Integer) }
    attr_reader :private_repo_count

    sig { returns(Integer) }
    attr_reader :public_repo_count

    sig { returns(Integer) }
    attr_reader :repo_count

    sig do
      params(
        owner: User,
        public_repo_count: Integer,
        repo_count: Integer,
        cursor: T.nilable(String),
        custom_patterns_query: T.nilable(String)
      ).void
    end
    def initialize(owner:, public_repo_count:, repo_count:, cursor:, custom_patterns_query: "")
      @owner = owner
      @private_repo_count = T.let(repo_count - public_repo_count, Integer)
      @public_repo_count = public_repo_count
      @repo_count = repo_count
      @cursor = cursor
      @custom_patterns_query = custom_patterns_query
    end

    private

    sig { returns(T::Boolean) }
    def show_private_vulnerability_reporting_settings?
      GitHub.private_vulnerability_reporting_enabled?
    end

    sig { returns(T::Boolean) }
    def security_configurations_enabled?
      @owner.security_configurations_enabled?
    end

    sig { returns(T::Boolean) }
    def button_disabled_no_repos?
      GitHub.enterprise? ? repo_count.zero? : private_repo_count.zero?
    end

    sig { params(title: String).returns(String) }
    def button_disabled_no_repos_title(title)
      button_disabled_no_repos? ? "No applicable repositories" : title
    end
  end
end
