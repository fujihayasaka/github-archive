# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "active_support"
require "active_support/core_ext"

module OctoCore
  extend T::Sig

  autoload :Api, "octo_core/api"
  autoload :AppEnvironment, "octo_core/app_environment"
  autoload :Auth, "octo_core/auth"
  autoload :Env, "octo_core/env"
  autoload :Context, "octo_core/context"
  autoload :Collection, "octo_core/collection"
  autoload :Decorator, "octo_core/decorator"
  autoload :Domain, "octo_core/domain"
  autoload :Env, "octo_core/env"
  autoload :Memoizer, "octo_core/memoizer"
  autoload :Middleware, "octo_core/middleware"
  autoload :Pagination, "octo_core/pagination"
  autoload :Result, "octo_core/result"
  autoload :Runtime, "octo_core/runtime"
  autoload :SecurityUtils, "octo_core/security_utils"
  autoload :Telemetry, "octo_core/telemetry"

  sig { returns(Context) }
  def self.context
    Context.instance
  end

  sig { returns(Auth::IdentityContext) }
  def self.identity_context
    context.identity_context
  end

  sig { returns(Runtime) }
  def self.runtime
    Runtime.instance
  end
end
