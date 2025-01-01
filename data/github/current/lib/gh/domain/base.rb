# typed: strict
# frozen_string_literal: true

module GH
  module Domain
    class Base
      extend T::Helpers
      extend GH::Decorator::Decorable

      include GitHub::Memoizer
      include Scientist

      MAX_REPOSITORY_ID_IN_CLAUSE_SIZE = 1000
      QUERY_BATCH_SIZE = 10_000

      unless GitHub::AppEnvironment.test?
        decorate_with GH::Decorator::Tracing
        decorate_with GH::Decorator::CallerAttribution
        decorate_with GH::Decorator::MysqlInstrumentation
      end

      decorate_with GH::Decorator::PackageContext
      decorate_with GH::Decorator::WrapPreloads

      abstract!

      sig { params(caller_service: Symbol, actor: T.nilable(Auth::Actor)).void }
      def initialize(caller_service, actor: nil)
        self.class.apply_decorators!
        @caller_service = caller_service
        @actor = actor
      end

      sig { returns(Symbol) }
      attr_reader :caller_service

      sig { returns(T.nilable(Auth::Actor)) }
      attr_reader :actor

      @_accessor_name = T.let(nil, T.nilable(String))

      sig { returns(T.nilable(String)) }
      def self.accessor_name
        @_accessor_name ||= begin
          namespace = T.must(name).split("::")
          accessor = namespace.last&.underscore

          # Repositories::Domain::KeyLink => key_link
          return accessor if accessor != "domain"

          # Stratocaster::Domain => nil
          nil
        end
      end

      protected

      sig { returns(Platform::Authorization::Permission) }
      memoize def permission
        Platform::Authorization::Permission.new(viewer: actor, origin: Platform::ORIGIN_INTERNAL)
      end

      private

      sig { params(length: Integer, name: String, tags: T::Array[String]).void }
      def log_list_size(length, name, tags = [])
        GitHub.dogstats.distribution(
          name,
          length,
          tags: tags += ["calling_catalog_service:#{self.caller_service.to_s.underscore}", "domain:#{self.class.accessor_name}"]
        )
      end
    end
  end
end
