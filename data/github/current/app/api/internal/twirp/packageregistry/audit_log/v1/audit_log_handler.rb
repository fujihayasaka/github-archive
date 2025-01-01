# typed: true
# frozen_string_literal: true

require "monolith-twirp-packageregistry-auditlog"

module Api::Internal::Twirp::Packageregistry
  module AuditLog
    module V1
      class AuditLogHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::Packageregistry::AuditLog::V1::AuditLogAPIService
        allow_access_for :client, allowed_clients: ["packageregistry"]

        def audit_log(req, env)
          if req.key.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "key")
          end

          if req.actor_id == 0
            return Twirp::Error.invalid_argument("must be non-empty", argument: "actor_id")
          end

          if req.msg.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "msg")
          end

          if req.package_type == :PACKAGE_TYPES_INVALID
            return Twirp::Error.invalid_argument("must be non-empty", argument: "package_type")
          end

          event = {
            actor_id: req.actor_id,
            actor: req.actor,
            org_id: req.org_id,
            org: req.org,
            repo_id: req.repo_id,
            repo: req.repo,
            pkg_id: req.pkg_id,
            pkg: req.pkg,
            package_type: req.package_type,
            msg: req.msg,
          }

          GitHub.instrument req.key, event.compact

          {
            msg: "success"
          }
        end
      end
    end
  end
end
