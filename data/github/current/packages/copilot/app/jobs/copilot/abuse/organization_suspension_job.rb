# typed: strict
# frozen_string_literal: true

module Copilot
  module Abuse
    class OrganizationSuspensionJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_organization_suspension_job

      retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 3

      resolve_tenant_context do |args|
        ::Organization.find_by(id: args[:organization_id])&.business
      end

      sig do
        params(
          organization_id: Integer,
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(organization_id:, payload: nil, actor_id: nil)
        source_event = payload&.[](:source_event)
        source_event_name = source_event.is_a?(String) && source_event.present? ? source_event : "unknown"

        actually_block = FeatureFlag.vexi.enabled?("copilot_organization_suspension_admin_block", default: false)

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.org.id" => organization_id,
          "gh.actor.id" => actor_id,
          "gh.copilot.source_event" => source_event_name,
          "gh.copilot.actually_block" => actually_block,
        ) do
          GitHub.dogstats.increment(
            "copilot.abuse.organization_suspension_job.invocations",
            tags: ["source_event:#{source_event_name}"]
          )

          GitHub.dogstats.distribution_time("copilot.abuse.organization_suspension_job.duration", tags: ["source_event:#{source_event_name}"]) do
            # Load users with seats from this organization, then keep only users without
            # another active seat from a different non-suspended organization.
            # These users are candidates for admin blocking.
            organization = ::Organization.find_by(id: organization_id)
            if organization.nil?
              GitHub.logger.info("Organization not found, skipping suspension")
              return
            end

            actor = actor_id && ::User.find_by(id: actor_id)
            if actor.nil?
              GitHub.logger.info("Blocking actor not found, skipping suspension blocks", "gh.copilot.actor_id" => actor_id)
              return
            end

            user_ids = with_write do
              Copilot::Seat
                .for_organization(organization)
                .distinct
                .pluck(:assigned_user_id)
            end

            if user_ids.empty?
              GitHub.logger.info("No users with seats found, skipping suspension")
              return
            end

            GitHub.logger.info(
              "Found users with seats in organization",
              "gh.copilot.user_count" => user_ids.size,
            )

            other_org_seats = with_write do
              Copilot::Seat
                .joins(:seat_assignment)
                .where(assigned_user_id: user_ids)
                .where.not(organization_id: organization.id)
                .where(copilot_seat_assignments: { access_revoked_at: nil })
                .distinct
                .pluck(:assigned_user_id, :organization_id)
            end

            organization_ids = other_org_seats.map { |_assigned_user_id, other_org_id| other_org_id }.compact.uniq
            GitHub.logger.info(
              "Found other org seats for users",
              "gh.copilot.other_org_seat_count" => other_org_seats.size,
              "gh.copilot.other_org_count" => organization_ids.size,
            )

            organizations_by_id = with_write do
              ::Organization.where(id: organization_ids).index_by(&:id)
            end

            user_ids_with_other_valid_org_seat = {}
            other_org_seats.each do |assigned_user_id, other_org_id|
              GitHub.logger.info(
                "Checking other org for user seat",
                "gh.copilot.assigned_user_id" => assigned_user_id,
                "gh.copilot.other_org_id" => other_org_id,
              )

              if other_org_id.nil?
                GitHub.logger.info(
                  "Other org ID is nil, skipping",
                  "gh.copilot.assigned_user_id" => assigned_user_id,
                )
                next
              end

              other_org = organizations_by_id[other_org_id]
              if other_org.nil?
                GitHub.logger.info(
                  "Other org not found, skipping",
                  "gh.copilot.assigned_user_id" => assigned_user_id,
                  "gh.copilot.other_org_id" => other_org_id,
                )
                next
              end

              if other_org.suspended?
                GitHub.logger.info(
                  "Other org is suspended, skipping",
                  "gh.copilot.assigned_user_id" => assigned_user_id,
                  "gh.copilot.other_org_id" => other_org_id,
                )
                next
              end

              user_ids_with_other_valid_org_seat[assigned_user_id] = true
            end

            user_ids_to_block = user_ids.reject { |user_id| user_ids_with_other_valid_org_seat[user_id] }
            if user_ids_to_block.empty?
              GitHub.logger.info("No users to block, skipping suspension")
              return
            end

            reason = "Org suspended; user has no alternate non-suspended Copilot seat source (org_id=#{organization_id})"

            ::User.where(id: user_ids_to_block).find_each do |user|
              GitHub.logger.info( # this will include actually_block from above named_tags
                "Blocking user due to organization suspension",
                "gh.user.id" => user.id,
                "reason" => reason,
              )

              Copilot::User.new(user).administrative_block!(
                actor,
                reason,
                skip_hammy_check: true,
                send_block_email: false,
                superban: false
              ) if actually_block
            end
          end
        end
      end
    end
  end
end
