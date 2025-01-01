# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class EnterpriseSeatEmissionJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_emission_job

      resolve_tenant_context do |enterprise_id|
        ::Business.find(enterprise_id)
      end

      # we are pulling the enterprise out to make sure that we don't have any users who are members of multiple organizations
      # within the same enterprise and aren't being billed if they have seats in the different organizations
      #
      # To do this, we load up all of the organizations in the enterprise and then load up all of the seats for the organizations
      #
      # we then want to iterate over the organizations and emit for each organization.
      # from here, we need to iterate over the organizations that are part of the enterprise and have active seats
      # for each one, we need to emit a seat emission for each user while making sure that a given user can only be
      # included in a single emission per enterprise
      sig { params(enterprise_id: Integer).void }
      def perform(enterprise_id)
        chatterbox_say("Starting Copilot::Billing::EnterpriseSeatEmissionJob for enterprise #{enterprise_id}")
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.business.id" => enterprise_id,
        ) do
          @enterprise_id = T.let(enterprise_id, T.nilable(Integer))

          # load up the enterprise - this is required so if it isn't there, report an exception. We might want to tweak this later
          @enterprise = T.let(::Business.find_by(id: T.must(@enterprise_id)), T.nilable(::Business))

          return handle_copilot_error(Copilot::Errors::SeatEmissionError.new("Invalid Enterprise"), { "gh.business.id" => @enterprise_id }) unless @enterprise

          copilot_business = Copilot::Business.new(@enterprise)

          # load up the organizations that are part of the enterprise and get their ids
          enterprise_organizations = @enterprise.organizations
          enterprise_organization_ids = enterprise_organizations.map(&:id)

          GitHub.logger.info(
            "Loaded organization ids for enterprise",
            "gh.business.organization_ids" => enterprise_organization_ids,
          )

          # Get the user ids of every user in the enterprise that has a seat
          enterprise_seats = if @enterprise.customer&.copilot_billed_on_billing_platform? || @enterprise.feature_enabled?(:copilot_mixed_licenses)
            copilot_business.seats_sorted_by_copilot_sku_by_org_id
          else
            copilot_business.seats_by_org_id.inject({}) do |acc, (org_id, seats)|
              acc[org_id] = seats.map(&:assigned_user_id) # we only care about the user ids
              acc
            end
          end

          if enterprise_seats.count == 0
            GitHub.logger.info("No seats found for enterprise")
            return
          end

          # let's find out which users are in multiple orgs
          user_ids = enterprise_seats.map(&:last).flatten
          multiple_org_user_ids = user_ids.flatten.select { |e| user_ids.count(e) > 1 }.uniq

          # For the augmented cancellation telemetry, we need to know if any of the shared user
          # have at least one active seat among all their seats. This is becuase pending cancellations
          # only meaningfully impact ARR when they are the only active seat for a user.
          users_with_at_least_one_active_seat = Set.new(
            Copilot::Seat
              .multi_org_users_with_active_seat(
                owner_ids: @enterprise.organizations.map(&:id),
                user_ids: multiple_org_user_ids
              )
              .map(&:assigned_user_id)
          )

          indexed_orgs = enterprise_organizations.index_by(&:id)

          already_billed_user_ids = Set.new

          enterprise_seats.each do |organization_id, seat_ids|
            Copilot::Billing::OrganizationSeatEmissionCommand.call(
              indexed_orgs[organization_id],
              already_billed_user_ids: already_billed_user_ids,
              active_seat_ids: users_with_at_least_one_active_seat
            )

            seat_ids.each do |assigned_user_id|
              next unless multiple_org_user_ids.include?(assigned_user_id)
              # we only want to add to this array if the user is actually in multiple orgs
              already_billed_user_ids << assigned_user_id
            end
          end
        end
        chatterbox_say("Finished Copilot::Billing::EnterpriseSeatEmissionJob for enterprise #{enterprise_id}")
      end
    end
  end
end
