# typed: strict
# frozen_string_literal: true

module OctoCore
  module Auth
    autoload :Actor, "octo_core/auth/actor"
    autoload :DefaultActor, "octo_core/auth/default_actor"
    autoload :Hmac, "octo_core/auth/hmac"
    autoload :IdentityContext, "octo_core/auth/identity_context"
    autoload :RequestHmacValidator, "octo_core/auth/request_hmac_validator"
  end
end
