# typed: true
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for setting an interaction limit for
#         an object.
module InteractionLimits
  class SetInteractionLimit

    VALID_LIMIT_INPUTS = RepositoryInteractionAbility::INTERACTION_LIMITS + [:no_limit]

    # inputs[:object] - The User, Organization, or Repository to set a limit for.
    # inputs[:limit] - The Symbol interaction limit name to set.
    # inputs[:duration] - The Symbol duration for the limit, one of they keys
    #                     from InteractionLimits::DURATION_OPTIONS.
    # inputs[:actor] - The User setting this limit.
    # inputs[:staff_actor] - A Boolean indicating if this action is being performed
    #                        via stafftools.
    def self.call(inputs)
      new(**inputs).call
    end

    def self.enum_to_limit_name(enum)
      return unless enum.present?
      case enum
      when "EXISTING_USERS"
        :sockpuppet_disallowed
      else
        enum.to_s.downcase.to_sym
      end
    end

    def initialize(
      object:,
      limit:,
      duration: RepositoryInteractionAbility::DURATION_OPTIONS.keys.first,
      actor:,
      staff_actor: false
    )
      @object      = object
      @limit       = limit
      @duration    = duration
      @actor       = actor
      @staff_actor = staff_actor
    end

    def call
      unless actor_can_set_interaction_limit?
        return Result.failure(
          object: object,
          error: "You are not authorized to set interaction limits.",
          platform_error: Platform::Errors::Forbidden,
        )
      end

      unless VALID_LIMIT_INPUTS.include?(limit)
        return Result.failure(
          object: object,
          error: "You must specify a valid limit.",
          platform_error: Platform::Errors::Unprocessable,
        )
      end

      unless RepositoryInteractionAbility::DURATION_OPTIONS.keys.include?(duration)
        return Result.failure(
          object: object,
          error: "You must specify a valid duration.",
          platform_error: Platform::Errors::Unprocessable,
        )
      end

      if interaction_ability.repository?
        if object.private?
          return Result.failure(
            object: object,
            error: "Interaction limits cannot be set for private repositories.",
            platform_error: Platform::Errors::Unprocessable,
          )
        end

        if interaction_ability.has_overall_limit?
          return Result.failure(
            object: object,
            error: "Cannot set an interaction limit for this repository because there is an active limit at the #{interaction_ability.active_limit_origin} level.",
            platform_error: Platform::Errors::Unprocessable,
          )
        end
      end

      if interaction_ability.set_ability(limit, actor, duration, staff_actor: staff_actor)
        Result.success(object: object)
      else
        Result.failure(
          object: object,
          error: "An error occurred when trying to set an interaction limit.",
          platform_error: Platform::Errors::Unprocessable,
        )
      end
    end

    class Result
      attr_reader :object, :success, :error, :platform_error
      alias_method :success?, :success

      def initialize(object:, success:, error:, platform_error:)
        @object         = object
        @success        = success
        @error          = error
        @platform_error = platform_error
      end

      def self.success(object:)
        new(
          error: nil,
          platform_error: nil,
          success: true,
          object: object,
        )
      end

      def self.failure(object:, error:, platform_error:)
        new(
          error: error,
          platform_error: platform_error,
          success: false,
          object: object,
        )
      end
    end

    private

    attr_reader :object, :limit, :duration, :actor, :staff_actor

    def interaction_ability
      @interaction_ability ||= RepositoryInteractionAbility.new(object)
    end

    def actor_can_set_interaction_limit?
      return true if staff_actor && actor.site_admin?
      object.can_set_interaction_limits?(actor)
    end
  end
end
