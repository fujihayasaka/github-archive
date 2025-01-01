# typed: true
# frozen_string_literal: true

module GitHub
  module Authentication
    class CAS
      class Strategy
        class ServiceTicketValidator < ::OmniAuth::Strategies::CAS::ServiceTicketValidator
          def initialize(configuration, return_to_url, ticket)
            super configuration, return_to_url, ticket
          end

          def user_info
            GitHub::Authentication.logger.info("gh.auth.cas.result" => find_authentication_success(get_service_response_body))
            super
          end
        end
      end
    end
  end
end
