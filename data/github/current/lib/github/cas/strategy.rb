# typed: true
# frozen_string_literal: true

require "omniauth/enterprise"

module OmniAuth
  module Strategies
    class CAS
      class ServiceTicketValidator
        def initialize(configuration, return_to_url, ticket)
          GitHub::Authentication.logger.info("code.namespace" => self.class.name, "code.function" => __method__, "omniauth.cas.configuration" => configuration, "omniauth.cas.return_to_url" => return_to_url, "omniauth.cas.ticket" => ticket)

          @configuration = configuration
          @uri = URI.parse(@configuration.service_validate_url(return_to_url, ticket))
        end

        def user_info
          auth_success = find_authentication_success(get_service_response_body)
          GitHub::Authentication.logger.info("code.namespace" => self.class.name, "code.function" => __method__, "omniauth.cas.result" => auth_success)
          parse_user_info(auth_success)
        end
      end

      # Public: Reconciles access by suspending or unsuspending the User record
      # when appropriate.
      #
      # user: User object to suspend/unsuspend
      def reconcile_access(user)
        if user.suspended? && GitHub.reactivate_suspended_user?
          ActiveRecord::Base.connected_to(role: :writing) do
            user.unsuspend("is granted access in external authentication system")
          end
        end
      end

      def find_user(uid)
        GitHub.auth.find_user(uid, nil)
      end

      protected

      def callback_phase_prelude
        ticket = request.params["ticket"]

        GitHub::Authentication.logger.with_named_tags("code.namespace" => self.class.name, "code.function" => __method__) do
          unless ticket
            GitHub::Authentication.logger.info("No CAS ticket")
            return fail!(:no_ticket, "No CAS Ticket")
          end

          validator = ::OmniAuth::Strategies::CAS::ServiceTicketValidator.new(@configuration, callback_url, ticket)

          @user_info = validator.user_info
          GitHub::Authentication.logger.with_named_tags("omniauth.user_info" => @user_info) do
            GitHub::Authentication.logger.info("Set user info")

            if @user_info.nil? || @user_info.empty?
              GitHub::Authentication.logger.info("Invalid CAS ticket")
              return fail!(:invalid_ticket, "Invalid CAS Ticket")
            end

            user, _ = find_user(@user_info["user"])
            reconcile_access(user) if user
          end
        end
      end

      def callback_phase
        callback_phase_prelude
        super
      end
    end
  end
end

module GitHub
  module Authentication
    class CAS
      class Strategy < ::OmniAuth::Strategies::CAS
        def initialize(app, options = {}, &block)
          super(app, options.dup, &block)
          GitHub::Authentication.logger.info("code.namespace" => self.class.name, "code.function" => __method__, "gh.auth.cas.options" => options, "gh.auth.cas.configuration" => @configuration)
        end

        protected

        def request_phase
          GitHub::Authentication.logger.info("code.namespace" => self.class.name, "code.function" => __method__, "gh.auth.cas.callback_url" => callback_url, "gh.auth.cas.login_url" => @configuration.login_url(callback_url))

          # delete REFERER from session, since we've added ?return_to the callback_url already
          @env["rack.session"].delete("omniauth.origin")

          super
        end
      end
    end
  end
end
