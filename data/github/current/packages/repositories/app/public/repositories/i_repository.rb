# typed: strict
# frozen_string_literal: true

module Repositories
  module IRepository
    extend T::Helpers

    include Kernel
    include FeatureFlag::IFeatureTarget

    requires_ancestor { Object }

    abstract!

    sig { abstract.returns(T::Boolean) }
    def advanced_security_configurable?; end

    sig { abstract.returns(T::Boolean) }
    def allows_forking?; end

    sig { abstract.returns(T::Boolean) }
    def anonymous_git_access_enabled?; end

    sig { abstract.returns(T::Boolean) }
    def new_record?; end

    sig { abstract.returns(T::Boolean) }
    def archived?; end

    sig { abstract.returns(T::Boolean) }
    def auto_merge_allowed?; end

    sig { abstract.params(serialize_login: Symbol).returns(String) }
    def clone_url_for_api(serialize_login: :default); end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def created_at; end

    sig { abstract.returns(T::Boolean) }
    def dco_signoff_enabled?; end

    sig { abstract.returns(String) }
    def default_branch; end

    sig { abstract.returns(T::Boolean) }
    def delete_branch_on_merge?; end

    sig { abstract.returns(String) }
    def description; end

    sig { abstract.returns(T::Boolean) }
    def disabled?; end

    sig { abstract.returns(T::Boolean) }
    def active?; end

    sig { abstract.returns(T::Boolean) }
    def discussions_active?; end

    sig { abstract.returns(Integer) }
    def disk_usage; end

    sig { abstract.returns(T::Boolean) }
    def enable_update_branch?; end

    sig { abstract.returns(T::Boolean) }
    def fork?; end

    sig { abstract.returns(Integer) }
    def forks_count; end

    sig { abstract.params(serialize_login: Symbol).returns(String) }
    def gitweb_url_for_api(serialize_login: :default); end

    sig { abstract.returns(T.nilable(String)) }
    def gitignore_template; end

    sig { abstract.returns(T::Boolean) }
    def has_downloads?; end

    sig { abstract.returns(T::Boolean) }
    def has_issues?; end

    sig { abstract.returns(T::Boolean) }
    def has_projects_enabled?; end

    sig { abstract.returns(T::Boolean) }
    def has_wiki?; end

    sig { abstract.returns(T.nilable(String)) }
    def homepage; end

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(T::Boolean)) }
    def is_importing?; end

    sig { abstract.returns(T.nilable(String)) }
    def license; end

    sig { abstract.returns(T.nilable(T::Boolean)) }
    def locked_on_migration?; end

    sig { abstract.returns(T::Boolean) }
    def merge_commit_allowed?; end

    sig { abstract.returns(T.nilable(String)) }
    def merge_commit_message_setting; end

    sig { abstract.returns(T.nilable(String)) }
    def merge_commit_title_setting; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.params(use: Symbol).returns(String) }
    def name_with_owner_for_api(use: :default); end

    sig { abstract.returns(String) }
    def name_with_display_owner; end

    sig { abstract.returns(String) }
    def name_with_owner; end

    sig { abstract.returns(T::Boolean) }
    def mirror?; end

    sig { abstract.returns(Integer) }
    def open_issues_count; end

    sig { abstract.returns(T.nilable(Users::IUser)) }
    def owner; end

    sig { abstract.returns(Promise[T.nilable(Users::IUser)]) }
    def async_owner; end

    sig { abstract.returns(T.nilable(Integer)) }
    def owner_id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def organization_id; end

    sig { abstract.returns(String) }
    def owner_default_new_repo_branch; end

    sig { abstract.returns(String) }
    def permalink; end

    sig { abstract.returns(T.nilable(String)) }
    def primary_language_name; end

    sig { abstract.returns(T::Boolean) }
    def public?; end

    sig { abstract.returns(T::Boolean) }
    def private?; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def pushed_at; end

    sig { abstract.returns(T::Boolean) }
    def rebase_merge_allowed?; end

    sig { abstract.returns(T::Boolean) }
    def squash_merge_allowed?; end

    sig { abstract.returns(T.nilable(String)) }
    def squash_merge_commit_message_setting; end

    sig { abstract.returns(T.nilable(String)) }
    def squash_merge_commit_title_setting; end

    sig { abstract.returns(T::Boolean) }
    def squash_pr_title_enabled?; end

    sig { abstract.returns(Integer) }
    def stargazer_count; end

    sig { abstract.params(serialize_login: Symbol).returns(String) }
    def ssh_url_for_api(serialize_login: :default); end

    sig { abstract.params(serialize_login: Symbol).returns(String) }
    def svn_url_for_api(serialize_login: :default); end

    sig { abstract.returns(T::Boolean) }
    def template?; end

    sig { abstract.returns(T::Array[String]) }
    def topic_names; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def updated_at; end

    sig { abstract.returns(String) }
    def visibility; end

    sig { abstract.returns(Integer) }
    def network_id; end

    sig { abstract.void }
    def touch; end
  end
end
