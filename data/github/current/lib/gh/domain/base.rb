# typed: strict
# frozen_string_literal: true

require "scientist"
require_relative "registration"

module GH
  module Domain
    class Base
      extend T::Helpers
      extend GH::Decorator::Decorable

      include GitHub::Memoizer
      include Scientist

      MAX_REPOSITORY_ID_IN_CLAUSE_SIZE = 10_000
      DEFAULT_REPOSITORY_ID_IN_CLAUSE_SIZE = 1_000
      QUERY_BATCH_SIZE = 10_000

      if !GitHub::AppEnvironment.test? && !GitHub.gitauth_host?
        decorate_with GH::Decorator::Tracing
        decorate_with GH::Decorator::CallerAttribution
        decorate_with GH::Decorator::MysqlInstrumentation
      end

      decorate_with GH::Decorator::PackageContext
      decorate_with GH::Decorator::WrapPreloads if !GitHub.gitauth_host?

      abstract!

      sig { void }
      def initialize
        self.class.apply_decorators!
      end

      sig { returns(T.nilable(Auth::Actor)) }
      def actor
        GH.identity_context.domain_actor
      end

      @_accessor_name = T.let(nil, T.nilable(String))

      sig { returns(String) }
      def self.accessor_name
        @_accessor_name ||= begin
          namespace = T.must(name).split("::")
          accessor = namespace.last&.underscore

          # Repositories::Domain::KeyLinks => key_link
          return accessor if accessor != "domain"

          # Stratocaster::Domain => stratocaster
          namespace.first&.underscore || "unknown"
        end
      end

      sig { returns(T::Hash[Symbol, T.class_of(GH::Domain::Base)]) }
      def self.accessors
        @accessors ||= T.let({}, T.nilable(T::Hash[Symbol, T.class_of(GH::Domain::Base)]))
      end

      sig { params(accessor_class: T.class_of(GH::Domain::Base), name: T.nilable(Symbol)).void }
      def self.accessor(accessor_class, name = nil)
        method_name = name || accessor_class.accessor_name.to_sym
        GH::Domain::Registration.register_domain_accessor(self, accessor_class, method_name)
        skip_decoration method_name
        accessors[method_name] = accessor_class
      end

      sig { returns(GH::Domain::Cache) }
      def cache
        @cache ||= begin
          T.let(
            GH::Domain::Cache.new(
              domain: GitHub.packageowners.package_for_type(self.class) || "unknown",
              accessor: self.class.accessor_name,
              registered_domain_namespace: GH::Domain::Registration.registered_namespace_for(self.class)
            ), T.nilable(GH::Domain::Cache)
          )
        end
      end

      protected

      sig { returns(Platform::Authorization::Permission) }
      def permission
        return T.must(@permission) if defined?(@permission) && @permission.present?

        @permission ||= T.let(
          Platform::Authorization::Permission.new(viewer: actor, origin: Platform::ORIGIN_INTERNAL),
          T.nilable(Platform::Authorization::Permission)
        )
      end

      private

      sig { params(length: Integer, name: String, tags: T::Array[String]).void }
      def log_list_size(length, name, tags = [])
        GitHub.dogstats.distribution(
          name,
          length,
          tags: tags += ["domain:#{self.class.accessor_name}"]
        )
      end
    end
  end
end
