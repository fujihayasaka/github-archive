# typed: strict
# frozen_string_literal: true

module Permissions
  module EntryPoint
    class HydroDecorator

      VALID_ACTOR_TYPES = T.let(
        %w[
          IntegrationInstallation
          OauthAuthorization
          OrganizationProgrammaticAccessGrant
          OrganizationProgrammaticAccessGrantRequest
          UserProgrammaticAccessGrant
          UserProgrammaticAccessGrantRequest
          ScopedIntegrationInstallation
          SiteScopedIntegrationInstallation
          User
        ].freeze,
        T::Array[String]
      )

      sig { params(actor_context: Permissions::EntryPoint::ActorContext).void }
      def initialize(actor_context)
        @actor_context = actor_context
      end

      sig { returns(T.any(Symbol, String)) }
      def actor_type
        return :ACTOR_TYPE_UNKNOWN unless VALID_ACTOR_TYPES.include?(@actor_context.actor_type)

        "ACTOR_TYPE_#{@actor_context.actor_type.underscore.upcase}"
      end

      sig { returns(T.any(Symbol, String)) }
      def target_type
        return :TARGET_TYPE_UNKNOWN if @actor_context.target_type.blank?

        "TARGET_TYPE_#{@actor_context.target_type.underscore.upcase}"
      end

      sig { returns(T.any(Symbol, String)) }
      def owner_type
        return :ACTOR_OWNER_TYPE_UNKNOWN if @actor_context.owner_type.blank?

        "ACTOR_OWNER_TYPE_#{@actor_context.owner_type.underscore.upcase}"
      end

      sig { returns(Symbol) }
      def write_type
        case @actor_context.write_type
        when WriteType::CREATE
          :WRITE_TYPE_CREATE
        when WriteType::UPDATE
          :WRITE_TYPE_UPDATE
        when WriteType::DELETE
          :WRITE_TYPE_DELETE
        else
          T.absurd(@actor_context)
        end
      end
    end
  end
end
