# typed: true
# frozen_string_literal: true

module ProgrammaticAccess
  class Destroyer
    def self.perform(access, explanation)
      new(access, explanation).perform
    end

    def initialize(access, explanation)
      @access = access
      @explanation = explanation
    end

    def perform
      GitHub.tracer.in_span("ProgrammaticAccess::destroy", kind: :internal) do |span|
        grant = @access.grant

        span.add_attributes(
          "gh.programmatic_access.owner.id" => @access.user_id,
          "gh.programmatic_access.permissions.count" => grant&.permission_records&.count || 0,
          "gh.programmatic_access.destroy_explanation" => @explanation&.to_s,
        )

        UserProgrammaticAccess.transaction do
          if @explanation.present?
            @access.destroy_with_explanation(@explanation)
          else
            @access.destroy!
          end
        end

        ProgrammaticAccessToken::Destroyer.perform(@access, @explanation)
      end
    rescue ActiveRecord::ActiveRecordError => err
      Failbot.report!(err)
      ProgrammaticAccessToken::Result.failed(err.message)
    end
  end
end
