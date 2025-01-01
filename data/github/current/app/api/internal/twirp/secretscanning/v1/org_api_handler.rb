# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class OrgAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Organizations::V1::OrganizationAPIService)

        allow_access_for :client

        BATCH_SIZE = 100

        exempt_from_tenant_context_requirement

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Organizations::V1::GetOrganizationRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              GitHub::Proto::SecretScanning::Organizations::V1::GetOrganizationResponse,
              Twirp::Error
            )
          )
        end
        def get_organization(req, env)
          unless req.organization.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization")
          end

          unless req.organization == :owner_id
            return Twirp::Error.invalid_argument("the organization is not a valid input", argument: "organization")
          end

          org = Organization.find_by(id: req.owner_id)

          unless org.present?
            return Twirp::Error.invalid_argument("failed to fetch organization", argument: "owner_id")
          end

          result = {
            id: org.id,
            login: org.login,
            spammy: org.spammy,
            global_relay_id: org.global_relay_id,
            created_at: Google::Protobuf::Timestamp.new(seconds: org.created_at.to_i),
            suspended: org.suspended?,
            spamurai_classification: spamurai_classification(org),
            billing_email: org.billing_email,
            business_id: org.business&.id.to_s,
          }

          GitHub::Proto::SecretScanning::Organizations::V1::GetOrganizationResponse.new({ organization: result })
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Organizations::V1::ListOrganizationsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              GitHub::Proto::SecretScanning::Organizations::V1::ListOrganizationsResponse,
              Twirp::Error
            )
          )
        end
        def list_organizations(req, env)
          unless req.business.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "business")
          end

          unless req.business == :business_id
            return Twirp::Error.invalid_argument("the business is not a valid input", argument: "business")
          end

          business = Business.find_by(id: req.business_id)

          organizations = []
          next_cursor = nil

          last_processed_org_id = 0
          if req.cursor.present?
            last_processed_org_id = req.cursor.unpack("Q")[0]
          end

          org_batch = T.must(business).organizations.where(::Organization.arel_table[:id].gt(last_processed_org_id))
          .order(:id)
          .limit(BATCH_SIZE)

          if org_batch.length != 0
            next_cursor = [T.must(org_batch.last).id].pack("Q")
            org_batch.map do |org|
              organizations.push({
                id: org.id,
                login: org.login,
                spammy: org.spammy,
                spamurai_classification: spamurai_classification(org),
                global_relay_id: org.global_relay_id,
                created_at: Google::Protobuf::Timestamp.new(seconds: org.created_at.to_i),
                suspended: org.suspended?,
                billing_email: org.billing_email,
                business_id: org.business&.id.to_s,
              })
            end
          end

          GitHub::Proto::SecretScanning::Organizations::V1::ListOrganizationsResponse.new({ organizations: organizations, next_cursor: next_cursor })
        end

        private

        def spamurai_classification(org)
          if org.spammy?
            :SPAMMY
          elsif org.hammy?
            :HAMMY
          else
            :SPAMURAI_CLASSIFICATION_UNKNOWN
          end
        end
      end
    end
  end
end
