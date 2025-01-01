# typed: false
# frozen_string_literal: true

require "monolith-twirp-proxima-enterprisemanagement"

module Api::Internal::Twirp::Proxima
  module EnterpriseManagement
    module V1
      # Handler for the MonolithTwirp::Proxima::EnterpriseManagement::V1::EnterpriseManagementAPIService
      class EnterpriseManagementAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["proxima"]
        handles_service MonolithTwirp::Proxima::EnterpriseManagement::V1::EnterpriseManagementAPIService
        connected_to_writing_for :create_enterprise
        exempt_from_tenant_context_requirement

        def before_rpc(rack_env, env)
          return Twirp::Error.not_found("Enterprise Management API not available outside of Proxima") unless GitHub.multi_tenant_enterprise?
        end

        # Public: Implementation of the ValidateEnterprise Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Proxima::EnterpriseManagement::V1::ValidateEnterpriseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Proxima::EnterpriseManagement::V1::ValidateEnterpriseResponse, or a Twirp::Error.
        def validate_enterprise(req, env)
          argument_error = check_required_params(req, require_shortcode: false)
          return argument_error if argument_error

          business_hash = create_business_hash(req)

          creator = Business::Creator.new(business_params: business_hash, require_owners: false)
          admin_email_valid = User.valid_email?(req.first_admin_user_email)

          is_successful = creator.valid? && admin_email_valid

          unless is_successful
            errors = creator.business.errors.full_messages
            errors.push("First admin user email invalid") unless admin_email_valid
          end

          {
            is_successful: is_successful,
            error_messages: errors
          }
        end

        # Public: Implementation of the CreateEnterprise Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Proxima::EnterpriseManagement::V1::CreateEnterpriseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Proxima::EnterpriseManagement::V1::CreateEnterpriseResponse, or a Twirp::Error.
        def create_enterprise(req, env)
          argument_error = check_required_params(req)
          return argument_error if argument_error

          business_hash = create_business_hash(req)
          creator = Business::Creator.new(business_params: business_hash, require_owners: false)

          if !creator.valid?
            log_failure(req, "create_enterprise", "Could not create Business: #{creator.error_message}")
            return Twirp::Error.invalid_argument("Could not create Business: #{creator.error_message}")
          end

          transaction_error = nil
          Business.transaction do
            creator.save!
            business = creator.business
            startups_program_status = business_startups_program_status(req)
            BusinessStartupsProgram.create_or_update!(creator.business, startups_program_status) if startups_program_status

            GitHub::CurrentTenant.set(business) do
              begin
                owner = business.create_and_add_first_emu_owner(email: req.first_admin_user_email, actor: nil, send_email_notification: false)
                if !owner
                  log_failure(req, "create_enterprise", "Owner undefined after create_and_add_first_emu_owner")
                  transaction_error = Twirp::Error.invalid_argument("Could not create First Admin Owner")
                  raise ActiveRecord::Rollback
                end
                EnterpriseManagedUserMailer.added_as_first_emu_business_admin(business, :owner, owner).deliver_later
              rescue ArgumentError, Business::UnableToCreateAdminUserError => e
                log_failure(req, "create_enterprise", "Could not create First Admin Owner: #{e.message}")
                transaction_error = Twirp::Error.invalid_argument("Could not create First Admin Owner: #{e.message}")
                raise ActiveRecord::Rollback
              end
            end
          end

          if creator.business.customer.persisted?
            creator.business.customer.onboard_to_all_billing_platform_products
          end

          return transaction_error if transaction_error
          {
            enterprise_id: creator.business.id
          }
        end

        def check_required_params(req, require_shortcode: true)

          if req.name.empty?
            log_failure(req, "check_required_params", "Name is a required field")
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name")
          end

          if req.slug.empty?
            log_failure(req, "check_required_params", "Slug is a required field")
            return Twirp::Error.invalid_argument("must be non-empty", argument: "slug")
          end

          if req.emu_short_code.empty? && require_shortcode
            log_failure(req, "check_required_params", "Emu Short Code is a required field")
            return Twirp::Error.invalid_argument("must be non-empty", arugment: "emu_short_code")
          end

          if req.seats <= 0
            log_failure(req, "check_required_params", "Seats must be greater than 0")
            return Twirp::Error.invalid_argument("must be a positive integer", arugment: "seats")
          end

          if req.billing_end_date.nil?
            log_failure(req, "check_required_params", "Billing End Date is a required field")
            return Twirp::Error.invalid_argument("must be non-empty", arugment: "billing_end_date")
          end

          if req.first_admin_user_email.empty?
            log_failure(req, "check_required_params", "First Admin User Email is a required field")
            Twirp::Error.invalid_argument("must be non-empty", arugment: "first_admin_user_email")
          end
        end

        def create_business_hash(req)
          {
            billing_email: req.billing_email,
            name: req.name,
            slug: req.slug,
            shortcode: req.emu_short_code,
            can_self_serve: req.can_self_serve.nil? ? true : req.can_self_serve,
            staff_owned: req.is_staff_owned,
            terms_of_service_type: terms_of_service_type(req),
            terms_of_service_notes: req.terms_of_service_notes,
            terms_of_service_company_name: req.terms_of_service_company_name,
            seats: req.seats,
            support_plan: support_plan(req),
            plan_duration: "month",
            business_type: "enterprise_managed",
            enterprise_web_business_id: req.enterprise_web_business_id,
            trial_expires_at: req.trial_expires_at ? "" : req.trial_expires_at,
            customer_attributes: { billing_end_date: req.billing_end_date.to_time, name: req.name, billing_type: "invoice", billing_attempts: 0, term_length: 12 },
            any_length_shortcode_feature_flag_enabled: false,
            owners: []
          }
        end

        def business_startups_program_status(req)
          return :year_1 if req.is_part_of_startup_program
        end

        def terms_of_service_type(req)
          case req.terms_of_service_type
          when :TOS_TYPE_CORPORATE
            "Corporate"
          when :TOS_TYPE_INVALID
            "Corporate"
          when :TOS_TYPE_CUSTOM
            "Custom"
          when :TOS_TYPE_CORPORATE_AND_EDUCATION
            "ESA+Education"
          else
            "Corporate"
          end
        end

        def support_plan(req)
          case req.support_plan
          when :SUPPORT_PLAN_INVALID
            "standard"
          when :SUPPORT_PLAN_STANDARD
            "standard"
          when :SUPPORT_PLAN_PREMIUM
            "premium"
          when :SUPPORT_PLAN_PREMIUM_PLUS
            "premium_plus"
          when :SUPPORT_PLAN_PREMIUM_PLUS_ENGINEERING_DIRECT
            "premium_plus_engineering_direct"
          when :SUPPORT_PLAN_PREMIUM_PLUS_ENGINEERING_DIRECT_PREMIER
            "premium_plus_engineering_direct_premier"
          when :SUPPORT_PLAN_PREMIUM_PLUS_ENGINEERING_DIRECT_UNIFIED_A
            "premium_plus_engineering_direct_unified_a"
          when :SUPPORT_PLAN_PREMIUM_PLUS_ENGINEERING_DIRECT_UNIFIED_P
            "premium_plus_engineering_direct_unified_p"
          when :SUPPORT_PLAN_EDUCATION
            "education"
          else
            "standard"
          end
        end

        def log_failure(req, rpc_method, error_message)
          GitHub.logger.error(
            "code.namespace" => "Api::Internal::Twirp::EnterpriseManagementAPI",
            "exception.message" => error_message,
            "code.function" => rpc_method
          )
        end
      end
    end
  end
end
