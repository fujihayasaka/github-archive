# typed: strict
# frozen_string_literal: true

module OctoCore
  class Runtime
    extend T::Sig
    include OctoCore::Memoizer

    sig { returns(Runtime) }
    def self.instance
      Thread.current[:octo_runtime] ||= new
    end

    sig { void }
    def initialize
      @current = T.let(nil, T.nilable(String))
    end

    sig { returns(T.nilable(String)) }
    def current
      @current ||=
        if File.exist?(current_runtime_path)
          File.read(current_runtime_path).chomp
        else
          current_from_environment
        end
    end

    sig { returns(T::Boolean) }
    def dotcom?
      current == "dotcom"
    end

    sig { returns(T::Boolean) }
    def enterprise?
      current == "enterprise"
    end

    sig { returns(T::Boolean) }
    memoize def multi_tenant_enterprise?
      multi_tenant_enterprise_environment?
    end

    private

    sig { returns(String) }
    def current_runtime_path
      "#{OctoCore::AppEnvironment.root}/tmp/runtime/current"
    end

    sig { returns(String) }
    def current_from_environment
      if enterprise_environment?
        "enterprise"
      else
        "dotcom"
      end
    end

    ENABLED_VALUES = %w(1 true)

    sig { returns(T::Boolean) }
    def enterprise_environment?
      %w(ENTERPRISE FI).any? { |var| ENABLED_VALUES.include?(ENV[var]) }
    end

    sig { returns(T::Boolean) }
    def multi_tenant_enterprise_environment?
      return false if enterprise_environment?
      ENABLED_VALUES.include?(ENV["MULTI_TENANT_ENTERPRISE"])
    end
  end
end
