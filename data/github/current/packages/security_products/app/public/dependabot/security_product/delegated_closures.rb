# typed: strict
# frozen_string_literal: true

module Dependabot
  module SecurityProduct
    class DelegatedClosures
      CONFIG_KEY_USER_ENABLED = "dependabot.delegated_closures.user_enabled"
      CONFIG_KEY_USER_DISABLED = "dependabot.delegated_closures.user_disabled"
      CLOSURE_EXEMPTION_REQUEST_TYPE = T.let("dependabot_alert_dismissal", String)
      MSG_LIMIT = 2048

      sig { returns(T.nilable(User)) }
      attr_reader :user

      sig { returns(T.nilable(Repository)) }
      attr_reader :repository

      sig { params(resource: T.any(Organization, Repository), user: T.nilable(User), resource_identifier: T.nilable(String)).void }
      def initialize(resource, user = nil, resource_identifier: nil)
        @resource = resource
        @user = user
        @resource_identifier = T.let(resource_identifier, T.nilable(String))
        @repository = T.let(extract_repository_from_resource(resource), T.nilable(Repository))
        @existing_dismissal_request = T.let(nil, T.nilable(Exemptions::ExemptionRequest))
      end

      sig { params(request: T.nilable(Exemptions::ExemptionRequest)).returns(T::Boolean) }
      def can_cancel_request?(request)
        return false if request.nil? || @user.nil?
        return false unless @resource.is_a?(Repository)
        return false unless enabled?
        # Only the requester or valid reviewers can cancel
        return false unless request.requester_id == @user.id || self.class.is_valid_reviewer?(@resource, @user)
        has_pending_request?
      end

      sig { returns(T::Boolean) }
      def show_request_button?
        return false if has_pending_request?
        return false if @user.nil?
        user_can_request_closure?(@user)
      end

      sig { returns(T::Boolean) }
      def show_cancel_button?
        return false unless has_pending_request?
        can_cancel_request?(existing_dismissal_request)
      end

      sig { returns(T::Boolean) }
      def can_enable?
        return false unless @resource.is_a?(Repository) && @resource.owner.is_a?(Organization)
        return false unless ::SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
        return false unless @resource.vulnerability_alerts_enabled?
        true
      end

      sig { returns(T::Boolean) }
      def feature_available?
        return false unless @resource.is_a?(Organization)

        # Check global Dependabot configuration first
        return false unless GitHub.dependabot_enabled?

        # Delegated closures is a Code Security feature.
        # For bundled GHAS, check that GHAS is purchased.
        # For split SKUs, check that Code Security is purchased.
        bundled = @resource.advanced_security_products_bundled?
        (bundled && !!@resource.advanced_security_purchased?) || (!bundled && @resource.code_security_purchased?)
      end

      sig { returns(T::Boolean) }
      def enabled?
        case @resource
        when Organization
          feature_available?
        when Repository
          repo_enabled?
        else
          T.absurd(@resource)
        end
      end

      sig { params(actor: User).void }
      def enable(actor:)
        unless @resource.is_a?(Repository)
          GitHub.logger.warn("DependabotDelegatedAlertClosures: enable called on non-Repository resource", {
            resource_type: @resource.class.name,
            resource_id: @resource.id,
          })
          return
        end

        @resource.config.enable(CONFIG_KEY_USER_ENABLED, actor)
        @resource.config.delete(CONFIG_KEY_USER_DISABLED, actor)
      end

      sig { params(actor: User).void }
      def disable(actor:)
        unless @resource.is_a?(Repository)
          GitHub.logger.warn("DependabotDelegatedAlertClosures: disable called on non-Repository resource", {
            resource_type: @resource.class.name,
            resource_id: @resource.id,
          })
          return
        end

        @resource.config.delete(CONFIG_KEY_USER_ENABLED, actor)
        @resource.config.enable(CONFIG_KEY_USER_DISABLED, actor)
      end

      sig { params(exemption_request: Exemptions::ExemptionRequest).returns(T::Boolean) }
      def display_review_buttons_for_closure_request?(exemption_request)
        return false unless @resource.is_a?(Repository)
        return false unless enabled?

        exemption_request.pending?
      end

      # NOTE: The UI currently uses `show_cancel_button?` (which calls `can_cancel_request?`) instead
      # of this method. This is kept for API consistency with Secret Scanning's
      # `display_cancel_button_for_closure_request?` and for potential future use (e.g., React payload builders).
      sig { params(actor: User, exemption_request: Exemptions::ExemptionRequest).returns(T::Boolean) }
      def display_cancel_button_for_closure_request?(actor, exemption_request)
        return false unless @resource.is_a?(Repository)
        return false unless enabled?

        # Only the requester or valid reviewers can cancel
        return false unless exemption_request.requester_id == actor.id || self.class.is_valid_reviewer?(@resource, actor)

        # The closure request status should be pending
        exemption_request.pending?
      end

      sig { params(actor: User).returns(T::Boolean) }
      def user_can_review_closure_requests?(actor)
        return false unless enabled?

        case @resource
        when Organization
          return true if Authz.domain.check_allowed(actor, :review_org_dependabot_alert_dismissal_requests, @resource)

          @resource.adminable_by?(actor)
        when Repository
          return false unless @resource.owner.is_a?(Organization)

          owner = T.cast(@resource.owner, Organization)
          return true if Authz.domain.check_allowed(actor, :review_org_dependabot_alert_dismissal_requests, owner)

          owner.adminable_by?(actor)
        else
          T.absurd(@resource)
        end
      end

      sig { params(actor: User).returns(T::Boolean) }
      def user_can_view_closure_requests?(actor)
        return false unless enabled?

        return true if user_can_view_closure_requests_via_delegated_permissions?(actor)

        user_can_view_regular_dependabot_alerts?(actor)
      end

      sig { params(actor: User).returns(T::Boolean) }
      def user_can_view_closure_requests_via_delegated_permissions?(actor)
        case @resource
        when Organization
          # Batch check multiple permissions in one call to reduce round trips to Authzd
          permissions = [
            :view_org_dependabot_alert_dismissal_requests,
            :review_org_dependabot_alert_dismissal_requests,
            :org_bypass_dependabot_alert_dismissal_requests,
          ]
          results = Authz.domain.check_multiple_permissions(actor, permissions, @resource)
          return true if results.values.any?

          @resource.adminable_by?(actor)
        when Repository
          return false unless @resource.owner.is_a?(Organization)

          owner = T.cast(@resource.owner, Organization)
          permissions = [
            :view_org_dependabot_alert_dismissal_requests,
            :review_org_dependabot_alert_dismissal_requests,
            :org_bypass_dependabot_alert_dismissal_requests,
          ]
          results = Authz.domain.check_multiple_permissions(actor, permissions, owner)
          return true if results.values.any?

          owner.adminable_by?(actor)
        else
          T.absurd(@resource)
        end
      end

      sig { params(actor: User).returns(T::Boolean) }
      def user_can_request_closure?(actor)
        return false unless enabled?

        case @resource
        when Organization
          return true if Authz.domain.check_allowed(actor, :manage_dependabot_alerts, @resource)
          return true if @resource.adminable_by?(actor)
          false
        when Repository
          return true if @resource.can_resolve_vulnerability_alerts?(actor)
          # Also check if user is an organization admin for org-owned repositories
          owner = @resource.owner
          return true if owner.is_a?(Organization) && owner.adminable_by?(actor)
          false
        else
          T.absurd(@resource)
        end
      end

      sig { params(actor: User).returns(T::Boolean) }
      def user_can_bypass_requests?(actor)
        case @resource
        when Organization
          return false unless enabled?
          self.class.can_bypass_dependabot_alert_dismissal_requests?(actor, @resource)
        when Repository
          # For user-owned repositories, delegated closures are not supported
          return false unless @resource.owner.is_a?(Organization)

          # If delegated closures are disabled at repo level, allow direct dismissal for anyone who can manage alerts
          return @resource.can_resolve_vulnerability_alerts?(actor) unless enabled?

          # If delegated closures are enabled, check org-level bypass permissions
          org_feature.user_can_bypass_requests?(actor)
        else
          T.absurd(@resource)
        end
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

      sig { params(requester: User, resource_id: String, reason: String, comment: T.nilable(String)).returns(Exemptions::ExemptionRequest) }
      def create_alert_closure_request(requester, resource_id, reason, comment)
        raise ArgumentError.new("Repository required for creating closure requests") unless @resource.is_a?(Repository)

        alert_number = resource_id.to_i
        if alert_number.zero?
          raise ArgumentError.new("resource ID must be an integer")
        end

        existing_request = existing_alert_closure_request(resource_id)
        # It's possible to create more than one alert closure request (e.g if the first one is denied or cancelled).
        # This is only a problem if the latest request is still open i.e not cancelled and not pending.
        if !existing_request.nil? && existing_request.status != "cancelled" && existing_request.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending
          GitHub.logger.info(
            "DependabotDelegatedAlertClosures: Tried to create closure request, but one already exists",
            "requester_id": requester.id,
            "requester_type": requester.class.name,
            "resource_id": resource_id,
            "repo_id": @resource.id,
            "exemption_request_ids": existing_request.id
          )
          raise ArgumentError.new("A request to dismiss this alert has already been made.")
        end

        # Find the alert to get its title
        alert = @resource.repository_vulnerability_alerts.find_by(number: alert_number)
        if alert.nil?
          raise ArgumentError.new("Alert not found")
        end

        GitHub.logger.info(
          "DependabotDelegatedAlertClosures: Creating closure request",
          "requester_id": requester.id,
          "requester_type": requester.class.name,
          "resource_id": resource_id,
          "repo_id": @resource.id
        )

        closure_request = Exemptions::ExemptionRequest.create!(
          requester: requester,
          resource_owner: @resource,
          resource_identifier: resource_id,
          repository: @resource,
          request_type: CLOSURE_EXEMPTION_REQUEST_TYPE,
          expires_at: 1.week.from_now.floor(0),
          metadata: {
            "reason": reason.to_s,
            "alert_title": "#{alert.package_name} - #{alert.open_source_vulnerability&.ghsa_id || 'Unknown'}",
            "alert_number": alert_number.to_s
          },
          requester_comment: comment,
        )

        GitHub.instrument("dependabot_closure_request.create", {
          actor: requester,
          repo: @resource,
          org: @resource.organization,
          number: closure_request.number,
          alert_number: resource_id,
          reason: reason,
          requester_comment: comment,
        })

        closure_request
      end

      sig { params(exemption_request: Exemptions::ExemptionRequest, status: String, message: T.nilable(String), user: User).returns([T.nilable(Exemptions::ExemptionResponse), T.nilable(String)]) }
      def review_exemption_request!(exemption_request:, status:, message:, user:)
        return [nil, "Repository required for review"] unless @resource.is_a?(Repository)
        return [nil, "User does not have permission to review dismissal requests"] unless self.class.is_valid_reviewer?(@resource, user)

        if status == "approve"
          alert_number = exemption_request.resource_identifier.to_i
          return [nil, "Invalid alert number - must be > 0"] unless alert_number > 0

          reason = exemption_request.metadata["reason"]

          if !is_valid_reason?(reason)
            return [nil, "Invalid resolution: #{reason}"]
          end

          requester = exemption_request.requester
          if requester.nil?
            return [nil, "Dismissal request has no requester"]
          end

          # Find and dismiss the alert
          alert = @resource.repository_vulnerability_alerts.find_by(number: alert_number)
          if alert.nil?
            return [nil, "Alert not found"]
          end

          if !alert.open?
            return [nil, "Alert is not open"]
          end

          # Dismiss the alert with the original requester's reason
          dismiss_success = begin
            alert.dismiss(actor: requester, reason: reason.to_sym, comment: exemption_request.requester_comment)
          rescue ArgumentError => e
            GitHub.logger.error("DependabotDelegatedAlertClosures: Invalid dismiss parameters", {
              error: e.message,
              alert_number: alert_number,
              exemption_request_id: exemption_request.id,
              reason: reason,
            })
            return [nil, "Invalid dismissal reason: #{reason}"]
          rescue ActiveRecord::RecordInvalid => e
            GitHub.logger.error("DependabotDelegatedAlertClosures: Failed to save alert dismissal", {
              error: e.message,
              alert_number: alert_number,
              exemption_request_id: exemption_request.id,
            })
            return [nil, "Failed to dismiss alert"]
          rescue => e
            GitHub.logger.error("DependabotDelegatedAlertClosures: Unexpected error dismissing alert", {
              error: e.message,
              error_class: e.class.name,
              alert_number: alert_number,
              exemption_request_id: exemption_request.id,
            })
            return [nil, "An unexpected error occurred while dismissing the alert"]
          end

          unless dismiss_success
            GitHub.logger.warn("DependabotDelegatedAlertClosures: Alert dismissal returned false", {
              alert_number: alert_number,
              exemption_request_id: exemption_request.id,
              alert_state: alert.state,
            })
            return [nil, "Alert could not be dismissed (it may no longer be open)"]
          end

          # Only create the approval response if dismiss succeeded
          res = Exemptions::ExemptionResponse.approve!(exemption_request, user, message: message)

          GitHub.instrument("dependabot_closure_request.approve", {
            actor: user,
            repo: @resource,
            org: @resource.organization,
            number: exemption_request.number,
            alert_number: exemption_request.resource_identifier,
            request_reviewer_comment: message,
          })
        elsif status == "reject" || status == "deny"
          res = Exemptions::ExemptionResponse.reject!(exemption_request, user, message: message)

          GitHub.instrument("dependabot_closure_request.deny", {
            actor: user,
            repo: @resource,
            org: @resource.organization,
            number: exemption_request.number,
            alert_number: exemption_request.resource_identifier,
            request_reviewer_comment: message,
          })
        else
          return nil, "Invalid status: #{status}"
        end
        [res, nil]
      end

      sig { params(exemption_request: Exemptions::ExemptionRequest, user: User).returns([T.nilable(T::Boolean), T.nilable(String)]) }
      def cancel_request!(exemption_request:, user:)
        return [nil, "Repository required for cancel"] unless @resource.is_a?(Repository)

        # Only the requester or valid reviewers can cancel
        unless exemption_request.requester == user || self.class.is_valid_reviewer?(@resource, user)
          return [nil, "Only the requester and reviewers can cancel requests"]
        end

        # Request can only be cancelled if still pending
        unless exemption_request.status.to_sym == :pending
          return [nil, "Request cannot be cancelled because it is #{exemption_request.status}"]
        end

        exemption_request.cancelled!

        GitHub.instrument("dependabot_closure_request.cancel", {
          actor: user,
          repo: @resource,
          org: @resource.organization,
          number: exemption_request.number,
          alert_number: exemption_request.resource_identifier,
        })

        # Send cancellation email to requester and all reviewers
        send_cancellation_email(exemption_request)

        [true, nil]
      end

      # Cancel a pending dismissal request when the underlying alert is dismissed directly.
      # This is an automated cleanup operation that bypasses the normal permission checks
      # since the actor has already been authorized to dismiss the alert directly.
      sig { params(exemption_request: Exemptions::ExemptionRequest, actor: T.nilable(User)).void }
      def cancel_request_for_alert_dismissal!(exemption_request:, actor:)
        return unless @resource.is_a?(Repository)
        return unless exemption_request.status.to_sym == :pending

        exemption_request.cancelled!

        GitHub.instrument("dependabot_closure_request.cancel", {
          actor: actor,
          repo: @resource,
          org: @resource.organization,
          number: exemption_request.number,
          alert_number: exemption_request.resource_identifier,
          reason: "alert_dismissed_directly",
        })
      end

      sig { params(repository: Repository, reviewer: T.any(User, PublicKey)).returns(T::Boolean) }
      def self.is_valid_reviewer?(repository, reviewer)
        # We don't support PublicKeys.
        return false if reviewer.is_a?(PublicKey)

        # At this point, reviewer must be a User since we ruled out PublicKey
        delegated_closures = new(repository, reviewer)
        delegated_closures.user_can_review_closure_requests?(reviewer)
      end

      # Get all user IDs who should receive email notifications for Dependabot alert dismissal requests
      # at the organization level. This includes:
      # - Users with the :review_org_dependabot_alert_dismissal_requests fine-grained permission
      # - Team members (where the team has the FGP)
      # - Business team members (if enterprise teams are enabled)
      # - Organization admins
      #
      # Used by the email notification system to determine who gets notified when a Dependabot
      # alert dismissal request is created.
      sig { params(org: Organization).returns(T::Array[Integer]) }
      def self.get_org_reviewer_ids(org)
        # Get all role IDs that have the review_org_dependabot_alert_dismissal_requests permission
        visible_role_ids = Authz.domain.roles.visible_org_role_ids_with_fgp(
          org, :review_org_dependabot_alert_dismissal_requests
        )

        # Get all actors (users, teams, business teams) assigned to these roles
        actor_types_and_ids = Authz.domain.user_roles.batch_role_assignments_with_role_ids_for_target(
          target: org, role_ids: visible_role_ids,
        )

        # Start with directly assigned users
        user_ids = actor_types_and_ids.fetch(User.user_role_target_type, [])

        # Add members of teams that have the permission
        team_ids = actor_types_and_ids.fetch(Team.user_role_target_type, [])
        user_ids.concat(Team.member_ids_of(team_ids, immediate_only: false))

        # Add members of business teams that have the permission (if feature is enabled)
        business_team_ids = []

        if org.business.present?
          business_team_ids = actor_types_and_ids.fetch(BusinessTeam.user_role_target_type, [])
          user_ids.concat(Orgs.domain.teams.user_ids_for_business_teams(business_team_ids))
        end

        # Include organization admins and ensure unique user IDs
        (user_ids + org.admin_ids).uniq
      end

      sig { params(repository: Repository, alert_number: Integer, viewer: User).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def self.get_timeline_events(repository:, alert_number:, viewer:)
        requests = Exemptions::ExemptionRequest.where(
          request_type: CLOSURE_EXEMPTION_REQUEST_TYPE,
          resource_identifier: alert_number.to_s,
          repository_id: repository.id,
        )

        events = []
        # Find the most recent pending request to show actions only on that one
        pending_requests = requests.select do |r|
          r.status != "cancelled" &&
          r.compute_status == Exemptions::ExemptionEvaluator::EvaluationResult::Pending
        end
        latest_pending_request = pending_requests.max_by(&:created_at)

        requests.each do |request|
          # Only show dismissal actions on the most recent pending request that's not cancelled
          show_dismissal_actions = latest_pending_request &&
                                  request == latest_pending_request &&
                                  is_valid_reviewer?(repository, viewer)

          events << DependabotAlerts::AlertTimelineEvent.new(
            type: :TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_REQUESTED,
            user_id: request.requester_id,
            timestamp: Google::Protobuf::Timestamp.new(seconds: request.created_at.to_i),
            resolution: request.metadata["reason"],
            resolution_note: request.requester_comment,
            request_id: request.id,
            show_dismissal_actions: show_dismissal_actions,
          )

          request.responses.each do |response|
            events << DependabotAlerts::AlertTimelineEvent.new(
              type: :TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_REVIEWED,
              user_id: response.reviewer_id,
              timestamp: Google::Protobuf::Timestamp.new(seconds: response.created_at.to_i),
              compute_status: response.status,
              reviewer_comment: response.message,
            )
          end

          if request.cancelled?
            events << DependabotAlerts::AlertTimelineEvent.new(
              type: :TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_CANCELLED,
              user_id: request.requester_id,
              timestamp: Google::Protobuf::Timestamp.new(seconds: request.updated_at.to_i),
            )
          end
        end

        events
      end

      sig { params(message: T.nilable(String)).returns([T::Boolean, T.nilable(String)]) }
      def self.validate_request_message(message)
        message ||= ""
        message = message.strip
        return false, "Message is required" if message.empty?
        return false, "Message exceeds #{MSG_LIMIT} character limit" if message.length > MSG_LIMIT
        [true, nil]
      end

      sig { params(actor: T.nilable(User), resource: T.any(Organization, Repository)).returns(T::Boolean) }
      def self.can_view_dependabot_alert_dismissal_requests?(actor, resource)
        return false if actor.nil?

        organization = if resource.is_a?(Organization)
          resource
        else
          resource.owner.is_a?(Organization) ? resource.owner : nil
        end

        return false if organization.nil?

        non_nil_actor = T.let(actor, User)
        non_nil_org = T.cast(organization, Organization)
        # Check via Authz to support both programmatic actors and custom roles
        Authz.domain.check_allowed(non_nil_actor, :view_org_dependabot_alert_dismissal_requests, non_nil_org) ||
          can_review_dependabot_alert_dismissal_requests?(actor, resource)
      end

      sig { params(actor: T.nilable(User), resource: T.any(Organization, Repository)).returns(T::Boolean) }
      def self.can_review_dependabot_alert_dismissal_requests?(actor, resource)
        return false if actor.nil?

        organization = if resource.is_a?(Organization)
          resource
        else
          resource.owner.is_a?(Organization) ? resource.owner : nil
        end

        return false if organization.nil?

        non_nil_actor = T.let(actor, User)
        non_nil_org = T.cast(organization, Organization)
        # Check via Authz to support both programmatic actors and custom roles
        Authz.domain.check_allowed(non_nil_actor, :review_org_dependabot_alert_dismissal_requests, non_nil_org)
      end

      sig { params(actor: T.nilable(User), resource: T.any(Organization, Repository)).returns(T::Boolean) }
      def self.can_bypass_dependabot_alert_dismissal_requests?(actor, resource)
        return false if actor.nil?

        organization = if resource.is_a?(Organization)
          resource
        else
          resource.owner.is_a?(Organization) ? resource.owner : nil
        end

        return false if organization.nil?

        non_nil_actor = T.let(actor, User)
        non_nil_org = T.cast(organization, Organization)
        # Check via Authz to support both programmatic actors and custom roles
        Authz.domain.check_allowed(non_nil_actor, :org_bypass_dependabot_alert_dismissal_requests, non_nil_org)
      end

      private

      sig { params(reason: T.untyped).returns(T::Boolean) }
      def is_valid_reason?(reason)
        reason.present? && reason.in?(RepositoryVulnerabilityAlert::DISMISS_REASONS.keys.map(&:to_s))
      end

      sig { params(actor: User).returns(T::Boolean) }
      def user_can_view_regular_dependabot_alerts?(actor)
        @regular_dependabot_alerts_visibility ||= T.let({}, T.nilable(T::Hash[User, T::Boolean]))
        return T.must(@regular_dependabot_alerts_visibility[actor]) if @regular_dependabot_alerts_visibility.key?(actor)

        case @resource
        when Organization
          @regular_dependabot_alerts_visibility[actor] = Authz.domain.check_allowed(actor, :view_dependabot_alerts, @resource)
        when Repository
          @regular_dependabot_alerts_visibility[actor] = @resource.can_view_vulnerability_alerts?(actor)
        else
          T.absurd(@resource)
        end
      end

      sig { returns(T::Boolean) }
      def repo_enabled?
        return false unless @resource.is_a?(Repository)
        return false unless @resource.owner.is_a?(Organization)

        return false unless org_feature.feature_available?

        # Ensure GHAS / Code Security is actually enabled on the repo
        return false unless CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository: @resource)

        # Check if disabled via security configuration
        return false if disabled_by_security_configuration?

        # Check if enabled via security configuration
        return true if enabled_by_security_configuration?

        # Check if explicitly disabled via repository configuration
        return false if @resource.config.enabled?(CONFIG_KEY_USER_DISABLED)

        # Check if delegated closures are enabled via repository configuration
        @resource.config.enabled?(CONFIG_KEY_USER_ENABLED)
      end

      sig { returns(T::Boolean) }
      def enabled_by_security_configuration?
        return false unless @resource.is_a?(Repository)
        return false unless @resource.owner.is_a?(Organization)

        applied_security_configuration&.dependabot_delegated_alert_dismissal_enabled? || false
      end

      sig { returns(T::Boolean) }
      def disabled_by_security_configuration?
        return false unless @resource.is_a?(Repository)
        return false unless @resource.owner.is_a?(Organization)

        applied_security_configuration&.dependabot_delegated_alert_dismissal_disabled? || false
      end

      sig { returns(T.nilable(SecurityConfiguration)) }
      def applied_security_configuration
        return nil unless @resource.is_a?(Repository)

        repo_config = @resource.repository_security_configuration
        return nil unless repo_config&.applied?

        repo_config.security_configuration
      end

      sig { returns(Dependabot::SecurityProduct::DelegatedClosures) }
      def org_feature
        return self if @resource.is_a?(Organization)

        @org_feature ||= T.let(
          if @resource.owner.is_a?(Organization)
            Dependabot::SecurityProduct::DelegatedClosures.new(T.cast(@resource.owner, Organization), @user)
          else
            nil
          end,
          T.nilable(Dependabot::SecurityProduct::DelegatedClosures)
        )
        T.must(@org_feature)
      end

      # Helper methods migrated from DelegatedClosuresPermissions
      sig { params(resource: T.any(Organization, Repository, RepositoryVulnerabilityAlert)).returns(T.nilable(Repository)) }
      def extract_repository_from_resource(resource)
        case resource
        when Repository
          resource
        when RepositoryVulnerabilityAlert
          resource.repository
        when Organization
          nil
        else
          T.absurd(resource)
        end
      end

      sig { returns(T::Boolean) }
      def has_pending_request?
        request = existing_dismissal_request
        !request.nil? && request.pending?
      end

      sig { returns(T.nilable(Exemptions::ExemptionRequest)) }
      def existing_dismissal_request
        return @existing_dismissal_request if @existing_dismissal_request
        return nil if @user.nil? || @repository.nil?

        query = {
          repository: @repository,
          request_type: CLOSURE_EXEMPTION_REQUEST_TYPE,
          status: "pending",
        }

        # When a resource_identifier is provided, scope the query to the specific alert
        # to avoid incorrectly matching pending requests for other alerts in the same repository
        query[:resource_identifier] = @resource_identifier if @resource_identifier

        @existing_dismissal_request = Exemptions::ExemptionRequest.find_by(query)
      end

      sig { params(exemption_request: Exemptions::ExemptionRequest).void }
      def send_cancellation_email(exemption_request)
        evaluator = exemption_request.evaluator
        return unless evaluator

        notification_configuration = evaluator.cancellation_notification_configuration(exemption_request)
        return unless notification_configuration

        # Get all reviewers who should be notified
        reviewer_ids = evaluator.notification_user_ids(exemption_request) || []
        reviewers = User.where(id: reviewer_ids).to_a

        # Combine requester and reviewers, deduplicate
        all_recipients = ([exemption_request.requester] + reviewers).uniq.compact

        # Send individual email to each recipient (matching the pattern for request creation)
        all_recipients.each do |recipient|
          ExemptionRequestMailer.alert_dismissal_request_cancelled(
            recipient,
            exemption_request,
            notification_configuration[:subject],
            notification_configuration[:reason],
            notification_configuration[:permalink]
          ).deliver_later
        end
      end
    end
  end
end
