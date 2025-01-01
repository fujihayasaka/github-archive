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

    sig { params(actor: Actor, permission: Symbol, subject: Subject).void }
    def initialize(actor:, permission:, subject:)
      @actor = T.let(actor, Actor)
      @permission = T.let(permission, Symbol)
      @subject = T.let(subject, Subject)
      @fine_grained_permission = T.let(Permissions::FineGrainedPermissionIm.find!(permission), Permissions::FineGrainedPermissionIm)
    end

    sig { returns(T::Hash[String, T.untyped]) }
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
          "subject.type" => subject.class.name
        }
      }
    end
  end
end
