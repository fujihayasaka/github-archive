# typed: strict
# frozen_string_literal: true

module Codespaces
  # Returns resume failover details for a given service stamp
  class GetFailoverDetails < Command
    extend T::Sig

    sig { returns(::User) }
    attr_reader :user

    sig { returns(Symbol) }
    attr_reader :vscs_target

    sig { returns(T.any(String, Codespaces::Locations::Region)) }
    attr_reader :region

    sig { returns(T::Boolean) }
    attr_reader :is_copilot_workspace

    sig { params(user: ::User, region: T.any(String, Codespaces::Locations::Region), vscs_target: Symbol, is_copilot_workspace: T::Boolean).void }
    def initialize(user:, region:, vscs_target:, is_copilot_workspace:)
      @user = user
      @vscs_target = vscs_target
      @region = region
      @is_copilot_workspace = is_copilot_workspace
    end

    sig { override.returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    def perform
      stamp = Codespaces::VscsServiceStamp.find(region:, vscs_target:)
      base_tags = ["location_reason:resume", "vscs_target:#{vscs_target}", "is_copilot_workspace:#{is_copilot_workspace}"]
      assignment_tags = base_tags + ["location:#{region}"]

      GitHub.dogstats.increment("codespaces.location_assignment", tags: assignment_tags)

      result = nil

      if stamp && !stamp.available_for_resumes?(user:)
        backup = stamp.backup(user:)

        if !backup
          GitHub.logger.warn(
            "Codespaces: No backups found for resumes.",
            "requested_region":  region.to_s,
            "vscs_target": vscs_target.to_s,
            "user": user
          )
        else
          failover_tags = base_tags + ["location:#{backup.region.id}"]
          GitHub.dogstats.increment("codespaces.location_assignment_rejected", tags: assignment_tags)
          GitHub.dogstats.increment("codespaces.location_assignment_reassigned", tags: failover_tags)
          result = { failoverEnabled: true, failoverRegion: backup.region.id }
        end
      end
      result
    end
  end
end
