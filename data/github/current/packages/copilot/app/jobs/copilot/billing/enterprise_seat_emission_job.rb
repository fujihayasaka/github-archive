# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class EnterpriseSeatEmissionJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_enterprise_seat_emission_job

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

          # TODO: remove this when we ship revokable access?
          if copilot_business.copilot_standalone?
            GitHub.logger.info("Processing enterprise team", "gh.copilot.seat_emission.business_id" => @enterprise_id)
            Copilot::Billing::EnterpriseTeamEmissionJob.perform_later(@enterprise.id)
            return
          end

          # load up the organizations that are part of the enterprise and get their ids
          enterprise_organizations = @enterprise.organizations
          enterprise_organization_ids = enterprise_organizations.map(&:id)

          GitHub.logger.info(
            "Loaded organization ids for enterprise",
            "gh.business.organization_ids" => enterprise_organization_ids,
          )

          # Get the user ids of every user in the enterprise that has a seat
          enterprise_seats = copilot_business.seats_sorted_by_copilot_sku_by_org_id

          if enterprise_seats.empty?
            GitHub.logger.info("No seats found for enterprise")
            return
          end

          # let's find out which users are in multiple orgs or who have seats associated with both the enterprise and an organization
          user_ids = enterprise_seats.map(&:last).flatten
          multi_seat_user_ids = user_ids.flatten.select { |e| user_ids.count(e) > 1 }.uniq

          indexed_orgs = enterprise_organizations.index_by(&:id)

          already_billed_user_ids = Set.new

          emit_copilot_license_snapshot(@enterprise, copilot_business)

          # `seats_sorted_by_copilot_sku_by_org_id` is already ordered by SKU priority, so we
          # iterate in that order to ensure higher-value org seats emit before enterprise-owned seats.
          enterprise_seats.each do |organization_id, seat_user_ids|
            # we want to check if either the organization_id is 0 (indicating the seat is associated with the enterprise directly)
            # or if the organization_id is not present in the indexed_orgs hash (indicating the organization
            # is not part of the enterprise anymore but we still need to emit for any seats)
            if organization_id.zero? || indexed_orgs[organization_id].nil?
              Copilot::Billing::PreviouslyBilledOrgSeatsFinder.find_already_billed_user_ids(
                copilot_business,
                seat_user_ids,
              ).each { |user_id| already_billed_user_ids << user_id }

              Copilot::Billing::EnterpriseSeatEmissionCommand.call(
                @enterprise,
                already_billed_user_ids: already_billed_user_ids,
              )
            else
              Copilot::Billing::OrganizationSeatEmissionCommand.call(
                indexed_orgs[organization_id],
                already_billed_user_ids: already_billed_user_ids,
              )
            end

            seat_user_ids.each do |assigned_user_id|
              next unless multi_seat_user_ids.include?(assigned_user_id)
              # We add to this set if:
              #   * The user is actually in multiple orgs
              #   * Has seats in both the enterprise and an organization
              already_billed_user_ids << assigned_user_id
            end
          end
        end
      end

      private

      sig { params(enterprise: ::Business, copilot_business: Copilot::Business).void }
      def emit_copilot_license_snapshot(enterprise, copilot_business)
        customer_id = enterprise.customer_id
        return unless customer_id

        counts = copilot_business.copilot_enabled_members_count_by_license

        copilot_for_business_count = counts[:business].to_i
        copilot_enterprise_count = counts[:enterprise].to_i

        return if copilot_for_business_count.zero? && copilot_enterprise_count.zero?

        Hydro::PublishRetrier.publish(
          {
            customer_id: customer_id.to_i,
            copilot_for_business_count: copilot_for_business_count,
            copilot_enterprise_count: copilot_enterprise_count,
          },
          schema: "billingplatform.v1.CopilotLicenseSnapshot",
          publisher: GitHub.hydro_publisher,
        )
      end
    end
  end
end
