# typed: strict
# frozen_string_literal: true

module Copilot
  class Types
    class Search < T::Enum
      enums do
        User = new("User")
        Team = new("Team")
        OrganizationInvite = new("OrganizationInvitation")
        DependentLicense = new("dependent")
        DirectLicense = new("direct")
      end
    end

    class SeatAssignment
      class Status < T::Enum
        enums do
          Creating = new("pending_creation")
          Unassigning = new("pending_unassignment")
          Reassigning = new("pending_reassignment")
          Cancelling = new("pending_cancellation")
          Stable = new("stable")
          Unassigned = new("unassigned")
        end
      end
    end

    SeatManagementIndexPayload = T.type_alias do
      {
        policy: String,
        seats: {
          seats: T::Array[SeatPayload],
          count: Integer,
          pending_requests: T.nilable(PendingRequestsPayload),
          licenses: Copilot::Types::CopilotLicenseIdentifiers,
        },
        seat_breakdown: {
          seats_assigned: Integer,
          seats_billed: Integer,
          seats_pending: Integer,
          description: String
        },
        organization: {
          name: String,
          id: T.nilable(Integer),
          billable: T::Boolean,
          has_seat: T::Boolean,
          add_seat_link: T.nilable(String),
          copilot_enabled: T::Boolean,
        },
        seat_assignments: Integer,
        business: T.nilable(BusinessPayload),
        public_code_suggestions_configured: T::Boolean,
        business_trial: T.nilable(TrialPayload),
        render_trial_expired_banner: T::Boolean,
        render_copilot_insights_banner: T::Boolean,
        can_add_teams: T::Boolean,
        members_count: Integer,
        can_allow_to_assign_seats_on_business: T::Boolean,
        plan_text: String,
        next_billing_date: ActiveSupport::TimeWithZone,
        featureRequestInfo: T.nilable(FeatureRequestInfo),
        render_pending_downgrade_banner: T::Boolean,
        display_activity: T::Boolean,
        adoption_metrics: CurrentAdoptionMetricsPayload,
      }
    end

    BusinessPayload = T.type_alias do
      {
        name: String,
        slug: String
      }
    end

    TrialPayload = T.type_alias do
      {
        started: T::Boolean,
        ended: T::Boolean,
        has_trial: T::Boolean,
        upgradable: T.nilable(T::Boolean),
        cancelable: T::Boolean,
        days_left: Integer,
        trial_length: Integer,
        started_at: ActiveSupport::TimeWithZone,
        ends_at: ActiveSupport::TimeWithZone,
        active: T::Boolean,
        expired: T::Boolean,
        pending: T::Boolean,
        copilot_plan: String,
        belongs_to_trial_business_account: T::Boolean,
      }
    end

    SeatPayload = T.type_alias do
      {
        assignable_type: String,
        pending_cancellation_date: T.nilable(Date),
        access_revoked_at: T.nilable(Date),
        last_activity_at: Time,
        assignable: AssignablePayload,
        invitation_date: T.nilable(ActiveSupport::TimeWithZone),
        invitation_expired: T.nilable(T::Boolean)
      }
    end

    AssignablePayload = T.type_alias do
      {
        id: Integer,
        login: T.nilable(String),
        avatar_url: T.nilable(String),
        display_name: T.nilable(String),
        slug: T.nilable(String),
        combined_slug: T.nilable(String),
        member_count: T.nilable(Integer),
        member_ids: T.nilable(T::Array[Integer]),
        email: T.nilable(String),
        invitee: T.nilable({
          id: T.nilable(Integer),
          login: String,
          display_name: T.nilable(String),
          avatar_url: String
        }),
      }
    end

    ModelPoliciesPayload = T.type_alias do
      {
        org_name: String,
        copilot_plan: String,
        enterprise_name: T.nilable(String),
        enterprise_slug: T.nilable(String),
        a_chat: T.nilable(PoliciesIndexPayloadNewAspect),
        a_f: T.nilable(PoliciesIndexPayloadNewAspect),
        afos: T.nilable(PoliciesIndexPayloadNewAspect),
        aofo: T.nilable(PoliciesIndexPayloadNewAspect),
        al: T.nilable(PoliciesIndexPayloadNewAspect),
        g_chat: T.nilable(PoliciesIndexPayloadNewAspect),
        g_tf: T.nilable(PoliciesIndexPayloadNewAspect),
        gtff: T.nilable(PoliciesIndexPayloadNewAspect),
        o1: T.nilable(PoliciesIndexPayloadNewAspect),
        o3: T.nilable(PoliciesIndexPayloadNewAspect),
        o_ff: T.nilable(PoliciesIndexPayloadNewAspect),
        o_fm: T.nilable(PoliciesIndexPayloadNewAspect),
        ofct: T.nilable(PoliciesIndexPayloadNewAspect),
        o_f: T.nilable(PoliciesIndexPayloadNewAspect),
        o_t: T.nilable(PoliciesIndexPayloadNewAspect),
        obmb: T.nilable(PoliciesIndexPayloadNewAspect),
        obmw: T.nilable(PoliciesIndexPayloadNewAspect),
        ofo: T.nilable(PoliciesIndexPayloadNewAspect),
        grok_code: T.nilable(PoliciesIndexPayloadNewAspect),
        copilot_for_dotcom_visible: T::Boolean,
        docsUrls: {
          generalPrivacyStatement: String,
        },
      }
    end

    PoliciesIndexPayload = T.type_alias do
      {
        org_name: String,
        copilot_plan: String,
        enterprise_name: T.nilable(String),
        enterprise_slug: T.nilable(String),
        editor_chat: PoliciesIndexPayloadNewAspect,
        mobile_chat: PoliciesIndexPayloadNewAspect,
        snippy: PoliciesIndexPayloadNewAspect,
        cli: PoliciesIndexPayloadAspect,
        editor_preview_features: PoliciesIndexPayloadNewAspect,
        agent_mode: PoliciesIndexPayloadNewAspect,
        automatic_code_review: PoliciesIndexPayloadNewAspect,
        copilot_for_dotcom: PoliciesIndexPayloadAspect,
        bing_github_chat: PoliciesIndexPayloadNewAspect,
        copilot_user_feedback_opt_in: PoliciesIndexPayloadOptInAspect,
        copilot_beta_features_opt_in: PoliciesIndexPayloadOptInAspect,
        copilot_extensions: PoliciesIndexPayloadAspect,
        private_telemetry: PoliciesIndexPayloadAspect,
        copilot_usage_metrics_policy: PoliciesIndexPayloadNewAspect,
        mcp: PoliciesIndexPayloadNewAspect,
        overages: {
          visible: T::Boolean,
          value: T::Boolean,
          copilot_premium_request: {
            value: T::Boolean,
            visible: T::Boolean,
          },
          coding_agent: {
            value: T::Boolean,
            visible: T::Boolean
          },
          spark: {
            value: T::Boolean,
            visible: T::Boolean,
          },
        },
        code_review: PoliciesIndexPayloadAspect,
        code_review_beta_features: PoliciesIndexPayloadOptInAspect,
        swe_agent: PoliciesIndexPayloadNewAspect,
        spark: PoliciesIndexPayloadNewAspect,
        insights: PoliciesIndexPayloadNewAspect,
        docsUrls: {
          generalPrivacyStatement: String,
        },
        desktop: PoliciesIndexPayloadNewAspect,
        mcp_registry: McpRegistryPolicyPayload,
        mcp_registry_access: McpRegistryPolicyPayload
      }
    end

    BillingOveragesPayload = T.type_alias do
      {
        visible: T::Boolean,
        value: T::Boolean,
        copilot_premium_request: {
          visible: T::Boolean,
          value: T::Boolean,
        },
        coding_agent: {
          visible: T::Boolean,
          value: T::Boolean
        },
        spark: {
          visible: T::Boolean,
          value: T::Boolean,
        },
      }
    end

    MetricsCatalogPayload = T.type_alias do
      {
        dashboards: T::Array[MetricsCatalogEntry],
      }
    end

    MetricsCatalogEntry = T.type_alias do
      {
        name: String,
        description: String,
        category: String,
        path: String,
      }
    end

    CurrentAdoptionMetricsPayload = T.type_alias do
      {
        total: Integer,
        active: Integer,
        inactive: Integer,
        dormant: Integer,
      }
    end

    AdoptionMetricsPayload = T.type_alias do
      {
        overallStartDate: Date,
        overallEndDate: Date,
        data: T::Array[AdoptionMetricsBucket],
      }
    end

    AdoptionMetricsBucket = T.type_alias do
      {
        id: String,
        label: String,
        shortLabel: String,
        startDate: Date,
        endDate: Date,
        total: Integer,
        active: Integer,
        inactive: Integer,
        dormant: Integer,
      }
    end

    CodeAcceptanceRatePayload = T.type_alias do
      {
        overallStartDate: Date,
        overallEndDate: Date,
        data: T::Array[CodeAcceptanceRateDateBucket],
      }
    end

    CodeAcceptanceRateDateBucket = T.type_alias do
      {
        id: String,
        label: String,
        shortLabel: String,
        startDate: Date,
        endDate: Date,
        lowEngagement: AcceptanceCounts,
        moderateEngagement: AcceptanceCounts,
        highEngagement: AcceptanceCounts,
      }
    end

    AcceptanceCounts = T.type_alias do
      {
        total: Integer,
        accepted: Integer,
        acceptanceRate: Float,
      }
    end

    AverageContributionPayload = T.type_alias do
      {
        overallStartDate: Date,
        overallEndDate: Date,
        data: T::Array[AverageContributionDateBucket],
      }
    end

    AverageContributionDateBucket = T.type_alias do
      {
        id: String,
        label: String,
        shortLabel: String,
        startDate: Date,
        endDate: Date,
        noCopilot: AverageCounts,
        lowEngagement: AverageCounts,
        moderateEngagement: AverageCounts,
        highEngagement: AverageCounts,
      }
    end

    AverageCounts = T.type_alias do
      {
        average: T.any(Float, Integer),
        percentDifference: T.nilable(Float)
      }
    end

    CollatedCopilotForBusinessConfigurations = T.type_alias do
      T::Array[
        T.any(
          { business: Copilot::Business, config: T.nilable(Copilot::Configuration) },
          { organization: Copilot::Organization, config: T.nilable(Copilot::Configuration) }
        )
      ]
    end

    MenuItemHashType = T.type_alias do
      {
        id: String,
        selected: T::Boolean,
        title: String,
        description: String,
        value: String
      }
    end

    PoliciesIndexPayloadAspect = T.type_alias do
      {
        manages: String,
        visible: T.nilable(T::Boolean),
        configurable: T::Boolean,
        options: T::Array[MenuItemHashType]
      }
    end

    PoliciesIndexPayloadNewAspect = T.type_alias do
      {
        manages: String,
        visible: T.nilable(T::Boolean),
        configurable: T::Boolean,
        options: T::Array[MenuItemHashType],
        helpurl: T.nilable(String),
        helptext: T.nilable(String),
        displayname: String,
        description: String,
        preview: T::Boolean,
      }
    end

    PoliciesIndexPayloadOptInAspect = T.type_alias do
      {
        manages: String,
        visible: T.nilable(T::Boolean),
        configurable: T::Boolean,
        enabled: T::Boolean,
      }
    end

    McpRegistryPolicyPayload = T.type_alias do
      {
        manages: String,
        displayname: T.nilable(String),
        description: T.nilable(String),
        visible: T::Boolean,
        configurable: T::Boolean,
        options: T.nilable(T::Array[MenuItemHashType]),
        helptext: T.nilable(String),
        helpurl: T.nilable(String),
        preview: T::Boolean,
        submitPath: String,
        mcpRegistryUrl: T.nilable(String),
        mcpRegistryId: T.nilable(Integer),
        isGA: T::Boolean
      }
    end

    License = T.type_alias do
      {
        type: T.any(Search::DirectLicense, Search::DependentLicense),
        name: T.nilable(String),
      }
    end

    MemberFeatureRequest = T.type_alias do
      {
        id: Integer,
        requested_at: ActiveSupport::TimeWithZone,
      }
    end

    FeatureRequestInfo = T.type_alias do
      {
        showFeatureRequest: T::Boolean,
        alreadyRequested: T::Boolean,
        dismissed: T::Boolean,
        featureName: String,
        requestPath: String,
        isEnterpriseRequest: T.nilable(T::Boolean),
        dismissedAt: T.nilable(String),
        billingEntityId: T.nilable(String),
        latestUsernameRequests: T::Array[String],
        amountOfUserRequests: Integer,
      }
    end

    PendingRequestsPayload = T.type_alias do
      {
        requesters: T::Array[RequesterPayload],
        count: Integer,
      }
    end

    RequesterPayload = T.type_alias do
      {
        id: T.nilable(Integer),
        display_login: String,
        profile_name: T.nilable(String),
        requested_at: T.nilable(ActiveSupport::TimeWithZone)
      }
    end

    SearchUserPayload = T.type_alias do
      {
        id: T.nilable(Integer),
        avatar_url: T.nilable(String),
        display_login: String,
        profile_name: T.nilable(String),
        org_member: T::Boolean,
        type: Search::User,
        feature_request: T.nilable(MemberFeatureRequest),
      }
    end

    SearchTeamPayload = T.type_alias do
      {
        id: T.nilable(Integer),
        avatar_url: T.nilable(String),
        name: T.nilable(String),
        slug: T.nilable(String),
        member_ids: T::Array[Integer],
        org_member: T::Boolean,
        type: Search::Team,
      }
    end

    SearchInvitePayload = T.type_alias do
      {
        id: T.any(T.nilable(Integer), NilClass),
        avatar_url: T.nilable(String),
        display_login: String,
        profile_name: T.nilable(String),
        org_member: T::Boolean,
        type: Search::OrganizationInvite,
      }
    end

    SearchAssignablesPayload = T.type_alias do
      {
        total: Integer,
        assignables: SearchAssignables,
      }
    end

    SearchAssignables = T.type_alias do
      T::Array[
        T.any(
          Copilot::Types::SearchUserPayload,
          Copilot::Types::SearchTeamPayload,
          Copilot::Types::SearchInvitePayload
        )
      ]
    end

    IgnoreIndexPayload = T.type_alias do
      {
        organization: String,
        last_edited: {
          login: String,
          time: Time
        },
      }
    end

    StandaloneBusinessSeatManagementIndexPayload = T.type_alias do
      {
        business: {
          slug: String,
          login: String,
        },
        count: Integer,
        filtered_count: Integer,
        total_seats: Integer,
        seatAssignments: T::Array[EnterpriseTeamAssignmentPayload]
      }
    end

    EnterpriseTeamAssignablePayload = T.type_alias do
      {
        id: Integer,
        mapping_id: T.nilable(Integer),
        slug: String,
        login: String,
        member_count: Integer,
        member_ids: T::Array[Integer],
      }
    end

    EnterpriseTeamAssignmentPayload = T.type_alias do
      {
        id: T.nilable(Integer),
        assignable_type: T.nilable(String),
        pending_cancellation_date: T.nilable(Date),
        last_activity_at: T.nilable(String),
        assignable: EnterpriseTeamAssignablePayload,
        status: String
      }
    end

    EnterpriseTeamWrapper = T.type_alias do
      T.any(Copilot::SeatAssignment, EnterpriseTeamAssignment, EnterpriseTeam)
    end

    SeatAssignmentWithStatus = T.type_alias do
      {
        entity: EnterpriseTeamWrapper,
        status: Copilot::Types::SeatAssignment::Status
      }
    end

    CopilotLicenseIdentifiers = T.type_alias do
      {
        user_ids: T::Array[Integer],
        team_ids: T::Array[Integer],
        invite_user_ids: T::Array[Integer],
        invite_emails: T::Array[String],
      }
    end

    CopilotEntity = T.type_alias do
      T.any(Copilot::User, Copilot::Organization, Copilot::Business)
    end

    OrgMutablePolicy = T.type_alias { T.all(Copilot::Policy, Copilot::Policies::Concerns::Organization::Mutable) }
  end
end
