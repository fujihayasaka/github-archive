# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class SecretRiskAssessmentsService
      include SecretScanning::Constants

      sig { params(org: Organization, user: User).returns([T.nilable(SecretScanning::Models::RiskAssessment::Assessment), T.nilable(SecretScanning::Errors::ServiceError)]) }
      def self.get_latest_assessment_for_org(org, user)
        owner = GitHub::Proto::SecretScanning::Types::V1::Owner.new(id: org.id, owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::ORGANIZATION_SCOPE)

        latest_response = GitHub::TokenScanning::Service::Client.new(user).get_latest_assessment(
          owner: owner,
        )

        if latest_response.nil?
          service_error = SecretScanning::Errors::ServiceError.new("An unknown error has occurred while fetching the latest assessment")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, organization_id: org.id, user_id: user.id)
          return nil, service_error
        end

        # if this is a 404, this is a valid case of assessment not found and not a service error
        if latest_response.error.present? && latest_response.error&.code == :not_found
          return nil, nil
        end

        if latest_response.error.present? || latest_response.data.nil? || latest_response.data.assessments.nil? || latest_response.data.assessments.nil?
          service_error = SecretScanning::Errors::ServiceError.new(latest_response.error&.msg || "An error has occurred while fetching the latest assessment")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, organization_id: org.id,  user_id: user.id)
          return nil, service_error
        end

        tokens_response = GitHub::TokenScanning::Service::Client.new(user).get_assessment_token_type_results(
          owner: owner,
          number: latest_response.data.assessments.first["Number"],
        )

        if tokens_response.nil?
          service_error = SecretScanning::Errors::ServiceError.new("An unknown error has occurred while fetching the latest assessment")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, organization_id: org.id, user_id: user.id)
          return nil, service_error
        end

        if tokens_response.error.present? || tokens_response.data.nil? || tokens_response.data.results.nil?
          service_error = SecretScanning::Errors::ServiceError.new(tokens_response.error&.msg || "An error has occurred while fetching the latest assessment")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, organization_id: org.id,  user_id: user.id)
          return nil, nil if tokens_response.error&.code == :not_found
          return nil, service_error
        end

        [SecretScanning::Models::RiskAssessment::Assessment.from_proto(latest_response.data, tokens_response.data), nil]
      end

      sig { params(org: Organization, user: User, marketing_info: T::Hash[Symbol, T.untyped]).returns(T.nilable(SecretScanning::Errors::ServiceError)) }
      def self.create_assessment_for_org(org, user, marketing_info)
        owner = GitHub::Proto::SecretScanning::Types::V1::Owner.new(id: org.id, owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::ORGANIZATION_SCOPE)

        response = GitHub::TokenScanning::Service::Client.new(user).create_assessment(
          owner: owner,
          requested_by_id: user.id,
        )

        if response.nil?
          service_error = SecretScanning::Errors::ServiceError.new("An unknown error has occurred while creating the assessment")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, organization_id: org.id, user_id: user.id)
          return service_error
        end

        if response.error.present?
          service_error = SecretScanning::Errors::ServiceError.new(response.error&.msg || "An error has occurred while creating the assessment")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, organization_id: org.id,  user_id: user.id)
          return service_error
        end

        begin
          enqueue_marketing_form_submission(org, user, marketing_info)
        rescue StandardError => e
          GitHub.logger.error("error submitting marketing form", {
            "exception.message": e.message,
            "code.namespace": "SecretScanning::Services::SecretRiskAssessmentsService",
            "code.function": "create_assessment_for_org",
            "gh.user.id": user.id,
            "gh.organization.id": org.id,
          })
        end

        nil
      end

      sig { params(org: Organization, user: User, marketing_info: T::Hash[Symbol, T.untyped]).void }
      def self.enqueue_marketing_form_submission(org, user, marketing_info)
        return if GitHub.enterprise?
        return if user.staff_user?

        return unless user.primary_user_email&.verified?
        return unless user.primary_user_email&.email.present?
        return unless user.primary_user_email&.email.match?(UserEmail::MarketingDependency::EMAIL_REGEX)
        return unless user.profile_name.present?
        return unless org.profile_location.present?


        marketo_data = {
          name: user.profile_name,
          email: user.primary_user_email&.email,
          country: org.profile_location,
          org_name: org.name,
          marketingConsent: nil,
          cDLProgramName: "477859",
          source: "In Product Interaction",
          sFDCLastCampaignStatus: "Responded",
          utm_campaign: marketing_info[:utm_campaign],
          utm_medium: marketing_info[:utm_medium],
          utm_source: marketing_info[:utm_source],
          utm_content: marketing_info[:utm_content],
        }.compact

        MarketingFormsSubmissionJob.perform_later(form_name: "secret-risk-assessment-product-form", raw_data: marketo_data)
      end

      sig { params(orgs: T::Array[Organization], user: User, assessment_number: T.nilable(Integer)).returns([T.nilable(String), T.nilable(SecretScanning::Errors::ServiceError)]) }
      def self.get_results_csv(orgs, user, assessment_number = nil)
        if orgs.length != 1
          return nil, SecretScanning::Errors::ServiceError.new("only one org supported for results csv")
        end

        org = T.must(orgs[0])
        org_id_to_names_map = {}
        org_id_to_names_map[org.id] = org.display_login

        options = {
          owner: GitHub::Proto::SecretScanning::Types::V1::Owner.new(id: org.id, owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::ORGANIZATION_SCOPE),
          org_ids_to_names: org_id_to_names_map,
          number: assessment_number
        }

        response = GitHub::TokenScanning::Service::Client.new(user).get_token_type_results_csv(options)

        if response.nil? || response.data.nil?
          service_error = SecretScanning::Errors::ServiceError.new("An unknown error has occurred while fetching the latest assessment")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, organization_id: org.id, user_id: user.id)
          return nil, service_error
        end

        if response.error.present?
          service_error = SecretScanning::Errors::ServiceError.new(response.error&.msg || "An error has occurred while fetching the latest assessment")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, organization_id: org.id,  user_id: user.id)
          return nil, service_error
        end

        [response.data.csv, nil]
      end
    end
  end
end
