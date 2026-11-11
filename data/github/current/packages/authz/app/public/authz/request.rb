# typed: strict
# frozen_string_literal: true

module Authz
  class Request
    include SorbetTypes

    sig { returns(Actor) }
    attr_reader :actor

    sig { returns(Symbol) }
    attr_reader :permission

    sig { returns(Subject) }
    attr_reader :subject

    sig { returns(Permissions::FineGrainedPermissionIm) }
    attr_reader :fine_grained_permission

    ORG_POLICY_VERSION = 1
    BUSINESS_POLICY_VERSION = 2

    # Feature flags which should be sent to Authzd as attributes
    # Only include active feature flags used by Authzd to evaluate generic policies
    FEATURE_FLAGS = T.let(%i[].freeze, T::Array[T.untyped])

    sig { params(actor: Actor, permission: Symbol, subject: Subject).void }
    def initialize(actor:, permission:, subject:)
      @actor = T.let(actor, Actor)
      @permission = T.let(permission, Symbol)
      @subject = T.let(subject, Subject)
      @fine_grained_permission = T.let(Permissions::FineGrainedPermissionIm.find!(permission), Permissions::FineGrainedPermissionIm)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def authzd_request_hash
      {
        action: :check_any_permission,
        subject: nil, # use only context-provided attributes
        actor: nil, # use only context-provided attributes
        context:
        {
          "permissions" => [fine_grained_permission.action] + fine_grained_permission.satisfied_by.flatten.uniq,
          "actor.id" => actor.id,
          "actor.type" => actor.class.name,
          "subject.id" => subject.id,
          "subject.type" => subject.class.name,
          "version" => policy_version,
          "feature_flags" => feature_flags,
        }
      }
    end

    private

    sig { returns(Integer) }
    def policy_version
      case @subject
      when Business
        BUSINESS_POLICY_VERSION
      when Organization
        ORG_POLICY_VERSION
      else
        T.absurd(@subject)
      end
    end

    sig { returns(T::Array[String]) }
    def feature_flags
      attrs = []
      if actor.respond_to?(:feature_flag_enabled?)
        FEATURE_FLAGS.each do |flag|
          attrs << flag if T.unsafe(actor).feature_flag_enabled?(flag, default: true)
        end
      end
      attrs
    end
  end
end
