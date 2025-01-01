# typed: strict
# frozen_string_literal: true

module Repositories
  module IRepository
    extend T::Helpers

    include Kernel
    include FeatureFlag::IFeatureTarget
    include ::CustomProperties::IPropertyTarget

    requires_ancestor { Object }

    abstract!

    sig { abstract.returns(T::Boolean) }
    def new_record?; end

    sig { abstract.returns(T::Boolean) }
    def archived?; end

    sig { abstract.params(serialize_login: Symbol).returns(String) }
    def clone_url_for_api(serialize_login: :default); end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def created_at; end

    sig { abstract.returns(String) }
    def description; end

    sig { abstract.returns(T::Boolean) }
    def disabled?; end

    sig { abstract.returns(T::Boolean) }
    def active?; end

    sig { abstract.returns(T::Boolean) }
    def deleted?; end

    sig { abstract.returns(Integer) }
    def disk_usage; end

    sig { abstract.returns(T::Boolean) }
    def fork?; end

    sig { abstract.returns(Integer) }
    def forks_count; end

    sig { abstract.params(serialize_login: Symbol).returns(String) }
    def gitweb_url_for_api(serialize_login: :default); end

    sig { abstract.returns(T.nilable(String)) }
    def gitignore_template; end

    sig { abstract.returns(String) }
    def global_relay_id; end # rubocop:disable GitHub/UntypedObjectId

    sig { abstract.returns(T::Boolean) }
    def has_downloads?; end

    sig { abstract.returns(T::Boolean) }
    def has_issues?; end

    sig { abstract.returns(T::Boolean) }
    def has_wiki?; end

    sig { abstract.returns(T.nilable(String)) }
    def homepage; end

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.params(use: Symbol).returns(String) }
    def name_with_owner_for_api(use: :default); end

    sig { abstract.returns(String) }
    def name_with_display_owner; end

    sig { abstract.returns(String) }
    def owner_display_login; end

    sig { abstract.returns(String) }
    def name_with_owner; end

    sig { abstract.returns(T.nilable(Users::IUser)) }
    def owner; end

    sig { abstract.returns(Promise[T.nilable(Users::IUser)]) }
    def async_owner; end

    sig { abstract.returns(T.nilable(Integer)) }
    def owner_id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def organization_id; end

    sig { abstract.params(include_host: T::Boolean).returns(String) }
    def permalink(include_host: true); end

    sig { abstract.returns(T.nilable(String)) }
    def primary_language_name; end

    sig { abstract.returns(T::Boolean) }
    def public?; end

    sig { abstract.returns(T::Boolean) }
    def private?; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def pushed_at; end

    sig { abstract.returns(Integer) }
    def stargazer_count; end

    sig { abstract.params(serialize_login: Symbol).returns(String) }
    def ssh_url_for_api(serialize_login: :default); end

    sig { abstract.params(serialize_login: Symbol).returns(String) }
    def svn_url_for_api(serialize_login: :default); end

    sig { abstract.returns(T::Boolean) }
    def template?; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def updated_at; end

    sig { abstract.returns(Integer) }
    def network_id; end

    sig { abstract.returns(T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]) }
    def custom_properties_effective_values; end

    sig { abstract.returns(T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]) }
    def system_properties_effective_values; end
  end
end
