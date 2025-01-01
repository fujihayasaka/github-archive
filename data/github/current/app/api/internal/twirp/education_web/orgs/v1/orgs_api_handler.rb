# typed: true
# frozen_string_literal: true
require "monolith-twirp-education_web-orgs"

module Api::Internal::Twirp::EducationWeb
  module Orgs
    module V1
      class OrgsApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["education_web"]
        handles_service MonolithTwirp::EducationWeb::Orgs::V1::OrgsAPIService
        connected_to_writing_for :revoke_outside_collaborators

        def revoke_outside_collaborators(req, env)
          org_login = req.org_login
          return Twirp::Error.invalid_argument("must be non-empty", argument: "org_login") if org_login.blank?
          revoke_collaborators = req.revoke
          return Twirp::Error.invalid_argument("must be non-empty", argument: "revoke_collaborators") if revoke_collaborators.nil?
          org = Organization.find_by_login(org_login)
          outside_collaborators = org.outside_collaborators
          revoked_unverified_outside_collaborators = []
          unverified_outside_collaborators = 0

          outside_collaborators.each do |outside_collaborator|
            current_coupon = outside_collaborator.coupon.code
            unless current_coupon.blank? || current_coupon.starts_with?("faculty-")
              unverified_outside_collaborators += 1
              begin
                org.remove_outside_collaborator(outside_collaborator) if revoke_collaborators
                revoked_unverified_outside_collaborators << outside_collaborator.id
              rescue => exception # rubocop:todo Lint/GenericRescue
                GitHub.logger.error(
                  "Failed to revoke outside collaborator",
                  "org_name" => org_login,
                  "user_id" => outside_collaborator.id,
                  "exception_message" => exception.message,
                  "exception_backtrace" => exception.backtrace
                )
              end
            end
          end
          GitHub.logger.info(
            "Revoked outside collaborators",
            "org_name" => org_login,
            "revoked_faculties" => revoked_unverified_outside_collaborators
          )
          { unverified_outside_collaborators_count: unverified_outside_collaborators, revoked_outside_collaborators_count: revoked_unverified_outside_collaborators.count }
        end
      end
    end
  end
end
