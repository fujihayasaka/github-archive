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

    STABLE_ORG_POLICY_VERSION = 1
    LATEST_ORG_POLICY_VERSION = 1

    # Warning: Before bumping the latest policy version, ensure the FF is at 0%
    # https://devportal.githubapp.com/feature-flags/authzd_use_latest_generic_business_policy_version/overview
    STABLE_BUSINESS_POLICY_VERSION = 2
    LATEST_BUSINESS_POLICY_VERSION = 2

    # Feature flags which should be sent to Authzd as attributes
    # Only include active feature flags used by Authzd to evaluate generic policies
    FEATURE_FLAGS = %i[enterprise_teams_attributes_include_business_teams].freeze

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
        subject.feature_flag_enabled?(:authzd_use_latest_generic_business_policy_version, default: false) ? LATEST_BUSINESS_POLICY_VERSION : STABLE_BUSINESS_POLICY_VERSION
      when Organization
        subject.feature_flag_enabled?(:authzd_use_latest_generic_org_policy_version, default: false) ? LATEST_ORG_POLICY_VERSION : STABLE_ORG_POLICY_VERSION
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
