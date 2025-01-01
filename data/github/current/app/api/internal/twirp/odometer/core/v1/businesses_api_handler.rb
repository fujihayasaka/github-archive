# typed: true
# frozen_string_literal: true

require "monolith-twirp-odometer-core"

module Api::Internal::Twirp::Odometer
  module Core
    module V1
      # Provides access to business data.
      class BusinessesAPIHandler < Api::Internal::Twirp::Handler
        include Api::Internal::Twirp::Odometer::Core::ActionsUsage

        handles_service(MonolithTwirp::Odometer::Core::V1::BusinessesAPIService)

        allow_access_for :user, :client, allowed_clients: %w(odometer).freeze

        GET_BUSINESSES_HARD_LIMIT = 100
        REPOSITORY_ORG_SAMPLE_LIMIT = 999

        # Public: Implementation of the GetBusinesses Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Odometer::Core::V1::GetBusinessesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of businesses, suitable for use in a
        # MonolithTwirp::Odometer::Core::V1::GetBusinessesResponse.
        def get_businesses(req, env)
          business_slugs = req.business_slugs.to_a
          business_ids = if business_slugs.any?
            Business.where(slug: business_slugs).pluck(:id)
          else
            req.business_ids.to_a
          end

          scope_or_error = businesses_for_business_ids(business_ids)

          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          elsif scope_or_error.is_a?(Hash)
            { businesses: scope_or_error.flat_map { |businesses| build_business_list(businesses) } }
          else
            { businesses: build_business_list(scope_or_error) }
          end
        end

        def default_user
          @default_user ||= User.staff_user
        end

        # Public: Implementation of the UpdateBusiness Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Odometer::Business::V1::UpdateBusinessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a business ID, suitable for use in a
        # MonolithTwirp::Odometer::Business::V1::UpdateBusinessResponse,
        # or a Twirp::Error if any updates were not successful.
        def update_business(req, env)
          business_id = req.business_id
          business = ::Business.where(id: business_id).first
          if !business
            return Twirp::Error.invalid_argument(
              "Business with ID #{business_id} does not exist",
              argument: "business_id"
            )
          end

          # converting trials and updating to volume should happen before updating other properties
          convert_trial = req.convert_trial
          if convert_trial && !Business.with_write { business.convert_trial(default_user, staff_initiated: true, switch_billing_to_invoice: true) }
            return Twirp::Error.internal("Failed to convert trial Business with ID #{business_id}")
          end
          # Mirrors EnterpriseLicensingController#transition_licensing_model
          if req.convert_to_volume&.value
            Business.with_write do
              transition = T.must(business.customer).new_licensing_model_transition(
                licensing_model: "volume",
                transition_date: Date.current,
              )
              begin
                transition.save!
              rescue ActiveRecord::ActiveRecordError
                return Twirp::Error.internal(
                  "Failed to convert to volume Business with ID #{business.id}: #{transition.errors.full_messages.join}")
              end
              transition.enqueue
            end
          end
          business.reload

          begin
            current_property = "seats"
            if req.seats && !Business.with_write { business.update(seats: req.seats.value) }
              return Twirp::Error.internal(
                "Failed to update property #{current_property} of Business with ID #{business.id}."
              )
            end

            current_property = "advanced_security_enabled_type_for_entity"
            if req.advanced_security_purchased
              update_advanced_security_enabled_type(
                business,
                req.advanced_security_purchased.value
              )
            end

            current_property = "advanced_security_seats_for_entity"
            if req.advanced_security_seats
              Business.with_write do
                begin
                  business.set_advanced_security_seats_for_entity(
                    seats: req.advanced_security_seats.value,
                    actor: default_user,
                    is_stafftools_action: true
                  )
                rescue Configurable::AdvancedSecurityBillingConfig::Error => err
                  return err
                end
              end
            end

            current_property = "trial_expires_at"
            if !convert_trial && (req.trial_duration || req.trial_extension)
              err = update_trial_expires_at(business, req.trial_duration, req.trial_extension)
              return err if err
            end

            current_property = "billing_end_date"
            if req.billing_end_date
              Business.with_write { T.must(business.customer).update(billing_end_date: req.billing_end_date.to_time) }
            end

            current_property = "sales_managed_trial"
            if req.sales_managed_trial && !Business.with_write { business.update(sales_managed_trial: req.sales_managed_trial.value) }
              return Twirp::Error.internal(
                "Failed to update property #{current_property} of Business with ID #{business.id}."
              )
            end

            current_property = "github_support_plan"
            if req.github_support_plan && !Business.with_write { business.support_plan = req.github_support_plan.value }
              return Twirp::Error.internal(
                "Failed to update property #{current_property} of Business with ID #{business.id}."
              )
            end

            current_property = "microsoft_support_plan"
            if req.microsoft_support_plan && !Business.with_write { business.microsoft_support_plan = req.microsoft_support_plan.value }
              return Twirp::Error.internal(
                "Failed to update property #{current_property} of Business with ID #{business.id}."
              )
            end

            current_property = "suspended"
            if req.suspended
              if !req.suspended_state_message
                return Twirp::Error.invalid_argument(
                  "suspended_state_message required",
                  argument: "suspended_state_message"
                )
              end
              if req.suspended.value
                if !Business.with_write { business.suspend(req.suspended_state_message.value, actor: User.staff_user, send_email: false) }
                  return Twirp::Error.internal(
                    "Failed to update property #{current_property} of Business with ID #{business.id}."
                  )
                end
              else
                if !Business.with_write { business.unsuspend(req.suspended_state_message.value, actor: User.staff_user) }
                  return Twirp::Error.internal(
                    "Failed to update property #{current_property} of Business with ID #{business.id}."
                  )
                end
              end
            end

            { business_id: business_id }
          rescue StandardError => err
            Twirp::Error.internal(
              "Failed to update property #{current_property} of Business with ID #{business.id}: #{err.message}"
            )
          end
        end

        private

        # Private: Convert an array of business ids into Business objects.
        #
        # business_ids - The array of business ids.
        #
        # Returns a scope of Business objects or a Twirp::Error
        def businesses_for_business_ids(business_ids, limit = GET_BUSINESSES_HARD_LIMIT)
          if business_ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}", argument: "business_ids")
          end

          ::Business.where(id: business_ids)
        end

        # Private: Convert an array of Business objects to the shape Twirp responses expect.
        #
        # businesses - The array of Business objects.
        #
        # Returns an array of Hash objects with business data that matches the Twirp definition.
        def build_business_list(businesses)
          businesses.map do |business|
            trial_state = begin
              if business.trial? && !business.trial_expired?
                "active_trial"
              elsif business.trial? && business.trial_expired?
                "expired_trial"
              else
                "converted"
              end
            end

            repository_count_sample = Repository.where(
              owner_id: Business::OrganizationMembership.where(business_id: business.id).limit(REPOSITORY_ORG_SAMPLE_LIMIT).pluck(:organization_id)
            ).count

            {
              id: business.id,
              slug: business.slug,
              emu: business.enterprise_managed?,
              created_at: protobuf_timestamp_if_present(business.created_at),
              trial_expires_at: protobuf_timestamp_if_present(business.trial_expires_at),
              invoice_end_at: protobuf_timestamp_if_present(business.billing_term_ends_on&.to_time(:utc)),
              trial_state:,
              idp_configured: business.external_provider_enabled?,
              user_count: business.total_consumed_licenses,
              seats_limit: business.total_purchased_licenses_with_overages,
              advanced_security_seats_limit: business.advanced_security_seats_for_entity,
              organization_count: business.organizations.count,
              repository_count_sample:,
              actions_limit: business_actions_limit(business),
              actions_consumed: actions_consumed(business),
              total_purchased_licenses: business.total_purchased_licenses,
              metered_ghe: business.metered_ghe,
              github_support_plan: business.support_plan,
              microsoft_support_plan: business.microsoft_support_plan,
              suspended: business.suspended?,
              sales_managed_trial: business.sales_managed_trial?,
              license_utilization_details: build_license_utilization_details(business),
            }
          end
        end

        # Private: Build the license utilization details for a business, matching stafftools
        def build_license_utilization_details(business)
          business = T.let(business, Business)
          business_organization_copilot_seats = 0
          business_copilot_standalone_seats = 0
          if business.seats_plan_basic?
            business_copilot_standalone_seats = ::Copilot::Seat.joins(:seat_assignment).where(copilot_seat_assignments: { owner_id: business.id }).count
          else
            business_organization_copilot_seats = ::Copilot::Seat.where(organization_id: business.organization_ids).pluck(:assigned_user_id).uniq.count
          end

          {
            #licensing platform
            licensing_platform: business.customer&.billed_via_billing_platform? ? "billing_platform" : "legacy_platform",
            # ghec
            purchased_enterprise_licenses: business.purchased_enterprise_licenses,
            consumed_enterprise_licenses: business.consumed_enterprise_licenses,
            available_enterprise_licenses: business.available_enterprise_licenses,
            purchased_volume_licenses: business.purchased_volume_licenses,
            volume_license_overages: business.volume_license_overages,
            purchased_volume_licenses_with_overages: business.purchased_volume_licenses_with_overages,
            consumed_volume_licenses: business.consumed_volume_licenses,
            available_volume_licenses_with_overages: business.available_volume_licenses_with_overages,
            total_purchased_licenses: business.total_purchased_licenses,
            total_purchased_licenses_with_overages: business.total_purchased_licenses_with_overages,
            total_consumed_licenses: business.total_consumed_licenses,
            total_available_licenses: business.total_available_licenses,
            # copilot
            seats_plan_basic: business.seats_plan_basic?,
            copilot_licensing_enabled: business.copilot_licensing_enabled?,
            business_organization_copilot_seats:,
            business_copilot_standalone_seats:,
            # ghas
            advanced_security_seats_for_entity: business.advanced_security_seats_for_entity,
            advanced_security_license_consumed_seats: business.advanced_security_license.consumed_seats,
            # billing
            metered_ghe: business.metered_ghe,
            has_zuora_id: business.zuora_account?,
            has_azure_id: business.linked_azure_subscription?,
            # ghas unbundled and metered
            advanced_security_products_bundled: business.advanced_security_products_bundled?,
            advanced_security_metered_for_entity: business.advanced_security_metered_for_entity?,
            advanced_security_secret_protection_seats_used: business.secret_protection.seats_used,
            advanced_security_secret_protection_seats_purchased: business.secret_protection.seats,
            advanced_security_code_security_seats_used: business.code_security.seats_used,
            advanced_security_code_security_seats_purchased: business.code_security.seats,
            advanced_security_maximum_committers: business.advanced_security_license_for_sku(sku: GitHub::Turboghas::SKU::Bundled).entity_summary.maximum_committers,
          }
        end

        # If the given value is present, format it as a protobuf timestamp. Otherwise, return nil.
        # @param value [Date, DateTime, nil]
        # @return [Google::Protobuf::Timestamp, nil]
        def protobuf_timestamp_if_present(value)
          return nil unless value.respond_to?(:to_time)

          Google::Protobuf::Timestamp.new(seconds: value.to_time.to_i)
        end

        # Private: Update the advanced security enabled type for a Business.
        #
        # business - The Business object to update.
        # advanced_security_purchased - The type of advanced security purchased, corresponding to one of:
        # - enabled (volume)
        # - enabled (metered)
        # - off
        #
        # Returns the result of updating the Business's advanced_security_enabled_type_for_entity property.
        def update_advanced_security_enabled_type(business, advanced_security_purchased)
          case advanced_security_purchased
          when "volume"
            advanced_security_enabled_type = Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME
          when "metered"
            advanced_security_enabled_type = Configurable::AdvancedSecurityBillingConfig::GHAS_METERED
          else
            advanced_security_enabled_type = Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF
          end

          Business.with_write do
            business.set_advanced_security_enabled_type_for_entity(
              option: advanced_security_enabled_type,
              actor: default_user,
              is_stafftools_action: true
            )
          end
        end

        # Private: Update the trial expiration date of a business.
        #
        # business - The Business object to update.
        # trial_duration - The new trial duration in days.
        # trial_extension - The number of days to extend the trial by.
        #
        # Returns an error if:
        # - Both trial_duration and trial_extension are set.
        # - The trial extension is negative.
        # - The business's trial expiration date failed to update.
        # Otherwise, returns nil.
        def update_trial_expires_at(business, trial_duration, trial_extension)
          if trial_duration && trial_extension
            return Twirp::Error.invalid_argument(
              "Both trial_duration and trial_extension cannot be set",
              argument: "trial_duration"
            )
          end

          current_trial_duration = (business.trial_expires_at.to_date - business.created_at.to_date).to_i

          if trial_duration
            trial_extension = trial_duration.value - current_trial_duration
          else
            trial_extension = trial_extension.value
          end

          if trial_extension > 0
            Business.with_write do
              extend_trial_result = business.extend_trial_days(default_user, T.let(trial_extension.days, ActiveSupport::Duration))
              if !extend_trial_result
                return Twirp::Error.internal("Failed to extend trial for Business with ID #{business.id}")
              end
            end
          else
            return Twirp::Error.invalid_argument(
              "The current trial duration of #{current_trial_duration} days must be extended by a positive number of days. Received request to extend trial by #{trial_extension} days.",
              argument: "trial_extension"
            )
          end

          nil
        end
      end
    end
  end
end
