# typed: strict
# frozen_string_literal: true

module DependencyGraph
  # Delegated closures for license compliance alerts
  #
  # These work a bit differently from other delegated closures because the osslicensecompliance (OLC) service is the
  # source of truth for license compliance alerts. While we may _display_ ExemptionRequests in the UI, the actions
  # taken on ExemptionRequests come via OLC.
  #
  # The general flow is:
  # 1. User takes some action in the UI
  # 2. The UI calls the monolith which validates permissions
  # 3. The monolith calls OLC to change the status on the alert
  # 4. OLC sends a Hydro message with the status change
  # 5. The monolith receives the Hydro message and updates the ExemptionRequest/ExemptionResponse accordingly
  #
  # Because of this flow, you don't see permissions checks here and may not see some of the feature flag checks
  # which are applied elsewhere.
  class LicenseComplianceDelegatedClosures
    CLOSURE_EXEMPTION_REQUEST_TYPE = T.let("license_compliance_dismissal", String)

    sig { returns(T.nilable(User)) }
    attr_reader :user

    sig { returns(T.nilable(Repository)) }
    attr_reader :repository

    sig { params(resource: T.any(Organization, Repository), user: T.nilable(User)).void }
    def initialize(resource, user = nil)
      @resource = resource
      @user = user
      @repository = T.let(extract_repository_from_resource(resource), T.nilable(Repository))
      @existing_dismissal_request = T.let(nil, T.nilable(Exemptions::ExemptionRequest))
    end

    sig { params(resource_id: String).returns(T.nilable(Exemptions::ExemptionRequest)) }
    def existing_alert_closure_request(resource_id)
      return nil unless @resource.is_a?(Repository)

      existing_requests_for_repo_and_alert = Exemptions::ExemptionRequest.not_expired.where(
        request_type: CLOSURE_EXEMPTION_REQUEST_TYPE,
        resource_owner_type: @resource.class.name,
        resource_owner_id: @resource.id,
        resource_identifier: resource_id,
      ).order(created_at: :desc)
      # Take the latest one
      existing_requests_for_repo_and_alert.first
    end

    sig { params(value: T.any(Symbol, Integer)).returns(T.nilable(String)) }
    def package_manager_name(value)
      # Start with the symbol part of the value. If it's an integer, look up the symbol.
      string_from_enum = if value.is_a?(Symbol)
        value
      else
        Hydro::Schemas::Github::Dependencygraph::V1::Entities::PackageManager.lookup(value)
      end

      # The return value is the enum name in lowercase without the "PACKAGE_MANAGER_" prefix
      string_from_enum.to_s.sub("PACKAGE_MANAGER_", "").downcase if string_from_enum
    end

    sig { params(alert: Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert).returns(String) }
    def resource_id_from_alert(alert)
      alert.alert_id.to_s
    end

    sig { params(requester: User, alert: Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert, comment: T.nilable(String)).returns([T.nilable(Exemptions::ExemptionRequest), T.nilable(String)]) }
    def create_alert_closure_request(requester, alert, comment)
      return [nil, "Repository required for creating closure requests"] unless @resource.is_a?(Repository)

      if alert.alert_id.zero?
        return [nil, "alert id must be present"]
      end

      resource_id = resource_id_from_alert(alert)

      existing_request = existing_alert_closure_request(resource_id)
      # It's possible to create more than one alert closure request (e.g if the first one is denied or cancelled).
      # This is only a problem if the latest request is still open i.e not cancelled and is pending.
      if !existing_request.nil? && existing_request.status != "cancelled" && existing_request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending
        GitHub.logger.info(
          "LicenseComplianceDelegatedClosures: Tried to create closure request, but one already exists",
          "requester_id": requester.id,
          "requester_type": requester.class.name,
          "resource_id": resource_id,
          "repo_id": @resource.id,
          "exemption_request_ids": existing_request.id
        )
        return [nil, "A request to dismiss this alert has already been made."]
      end

      metadata = {
        "alert_title": "Non-compliant license expression found on #{alert.package_name}",
        "alert_id": alert.alert_id.to_s,
        "alert_number": alert.alert_number.to_s,
      }

      closure_reason = alert.closure_reason
      if closure_reason.is_a?(Symbol)
        human_readable_reason = DependencyGraph::LicenseComplianceDismissalOptions.label_for_closure_reason(closure_reason)
        metadata[:reason] = human_readable_reason if human_readable_reason
      end

      closure_request = Exemptions::ExemptionRequest.create!(
        requester: requester,
        resource_owner: @resource,
        resource_identifier: resource_id,
        repository: @resource,
        request_type: CLOSURE_EXEMPTION_REQUEST_TYPE,
        expires_at: 30.days.from_now.floor(0),
        metadata: metadata,
        requester_comment: comment,
      )

      GitHub.instrument("license_compliance_closure_request.create", {
        actor: requester,
        repo: @resource,
        org: @resource.organization,
        number: closure_request.number,
        alert_number: resource_id,
        requester_comment: comment,
      })

      [closure_request, nil]
    end

    sig { params(reviewer: User, alert: Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert, comment: T.nilable(String)).returns([T.nilable(Exemptions::ExemptionResponse), T.nilable(String)]) }
    def approve_request!(reviewer, alert, comment)
      return [nil, "Repository required for review"] unless @resource.is_a?(Repository)
      resource_id = resource_id_from_alert(alert)
      request = existing_alert_closure_request(resource_id)
      return [nil, "No existing dismissal request for alert #{alert.alert_number}"] if request.nil?

      res = Exemptions::ExemptionResponse.approve!(request, reviewer, message: comment)

      GitHub.instrument("license_compliance_closure_request.approve", {
        actor: reviewer,
        repo: @resource,
        org: @resource.organization,
        number: request.number,
        alert_number: request.resource_identifier,
        request_reviewer_comment: comment,
      })

      [res, nil]
    end

    sig { params(reviewer: User, alert: Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert, comment: T.nilable(String)).returns([T.nilable(Exemptions::ExemptionResponse), T.nilable(String)]) }
    def deny_request!(reviewer, alert, comment)
      return [nil, "Repository required for review"] unless @resource.is_a?(Repository)
      resource_id = resource_id_from_alert(alert)
      request = existing_alert_closure_request(resource_id)
      return [nil, "No existing dismissal request for alert #{alert.alert_number}"] if request.nil?

      res = Exemptions::ExemptionResponse.reject!(request, reviewer, message: comment)

      GitHub.instrument("license_compliance_closure_request.deny", {
        actor: reviewer,
        repo: @resource,
        org: @resource.organization,
        number: request.number,
        alert_number: request.resource_identifier,
        request_reviewer_comment: comment,
      })

      [res, nil]
    end

    # Helper methods migrated from DelegatedClosuresPermissions
    sig { params(resource: T.any(Organization, Repository)).returns(T.nilable(Repository)) }
    def extract_repository_from_resource(resource)
      case resource
      when Repository
        resource
      when Organization
        nil
      else
        T.absurd(resource)
      end
    end

    # Get all user IDs who should receive email notifications for license compliance alert dismissal requests
    # at the organization level. We only notify people who explicitly have the fine-grained permission.
    #
    # During the transition from the enterprise-level FGP to the org-level FGP, two flags gate behavior:
    # - When :dependency_graph_eoslm_switch is enabled, notifications are driven solely by the org-level
    #   :review_license_compliance_closure_requests FGP.
    # - When :dependency_graph_eoslm_switch is disabled and :dependency_graph_eoslm_role is enabled,
    #   notifications are the deduped union of the new org-level FGP and the legacy enterprise-level
    #   :review_enterprise_license_alert_dismissal_requests FGP, so reviewers granted either permission are
    #   notified during rollout.
    # - When both flags are disabled, notifications fall back to the legacy enterprise-level FGP only.
    #
    # Used by the email notification system to determine who gets notified when a license compliance
    # alert dismissal request is created.
    sig { params(org: Organization).returns(T::Array[Integer]) }
    def self.get_org_reviewer_ids(org)
      if FeatureFlag.vexi.enabled?(:dependency_graph_eoslm_switch, org, org.business, default: false)
        get_org_reviewer_ids_via_org_fgp(org)
      elsif FeatureFlag.vexi.enabled?(:dependency_graph_eoslm_role, org, org.business, default: false)
        # Enterprise path must run first: the org path mutates shared Authz.domain.user_roles state that would leak a role_id filter into the enterprise query.
        (get_org_reviewer_ids_via_enterprise_fgp(org) + get_org_reviewer_ids_via_org_fgp(org)).uniq
      else
        get_org_reviewer_ids_via_enterprise_fgp(org)
      end
    end

    sig { params(org: Organization).returns(T::Array[Integer]) }
    private_class_method def self.get_org_reviewer_ids_via_org_fgp(org)
      visible_role_ids = Authz.domain.roles.visible_org_role_ids_with_fgp(
        org, :review_license_compliance_closure_requests
      )

      actor_types_and_ids = Authz.domain.user_roles.batch_role_assignments_with_role_ids_for_target(
        target: org, role_ids: visible_role_ids,
      )

      user_ids = actor_types_and_ids.fetch(User.user_role_target_type, [])

      team_ids = actor_types_and_ids.fetch(Team.user_role_target_type, [])
      user_ids.concat(Team.member_ids_of(team_ids, immediate_only: false))

      if org.business.present?
        business_team_ids = actor_types_and_ids.fetch(BusinessTeam.user_role_target_type, [])
        user_ids.concat(Orgs.domain.teams.user_ids_for_business_teams(business_team_ids))
      end

      user_ids.uniq
    end

    sig { params(org: Organization).returns(T::Array[Integer]) }
    private_class_method def self.get_org_reviewer_ids_via_enterprise_fgp(org)
      return [] unless org.business.present?

      # Get enterprise role IDs visible for this business that include the specific fine-grained permission.
      enterprise_role_ids = EnterpriseRole.visible_roles(T.must(org.business)).map(&:id)
      return [] if enterprise_role_ids.empty?

      visible_role_ids = Role.joins(:permissions)
        .where(id: enterprise_role_ids, permissions: { action: :review_enterprise_license_alert_dismissal_requests })
        .distinct
        .limit(EnterpriseRole::ENTERPRISE_CUSTOM_ENT_ROLE_LIMIT)
        .pluck(:id)
      return [] if visible_role_ids.empty?

      # Get all actors (users, teams, business teams) assigned to these enterprise roles with access to this org.
      actor_types_and_ids = Authz.domain.user_roles.actors_with_enterprise_roles_for_org(
        enterprise_role_ids: visible_role_ids,
        org: org
      )

      # Start with directly assigned users
      user_ids = actor_types_and_ids.fetch(User.user_role_target_type, [])

      # Add members of teams that have the permission
      team_ids = actor_types_and_ids.fetch(Team.user_role_target_type, [])
      user_ids.concat(Team.member_ids_of(team_ids, immediate_only: false))

      # Add members of business teams that have the permission (if feature is enabled)
      business_team_ids = actor_types_and_ids.fetch(BusinessTeam.user_role_target_type, [])
      user_ids.concat(Orgs.domain.teams.user_ids_for_business_teams(business_team_ids)) if business_team_ids.any?

      # Ensure unique user IDs
      user_ids.uniq
    end
  end
end
