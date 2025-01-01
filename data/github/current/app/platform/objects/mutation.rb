# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Mutation < Platform::Objects::Base
      # Don't return a promise from this, because we want GraphQL-Ruby to run these fields right away
      def self.authorized?(*)
        super.sync # rubocop:disable GitHub/DontSyncInsideFields
      end

      def self.async_viewer_can_see?(*)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      def self.async_api_can_access?(*)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      description "The root query for implementing GraphQL mutations."

      field :add_reaction, mutation: Mutations::AddReaction
      field :remove_reaction, mutation: Mutations::RemoveReaction
      field :update_subscription, mutation: Mutations::UpdateSubscription

      # Collections
      field :update_explore_collection, mutation: Mutations::UpdateExploreCollection

      # Comments
      field :add_comment, mutation: Mutations::AddComment
      field :minimize_comment, mutation: Mutations::MinimizeComment
      field :unminimize_comment, mutation: Mutations::UnminimizeComment
      field :delete_comment, mutation: Mutations::DeleteComment
      field :update_issue_comment, mutation: Mutations::UpdateIssueComment
      field :submit_abuse_report, mutation: Mutations::SubmitAbuseReport

      # Newsies
      field :mark_all_notifications, mutation: Mutations::MarkAllNotifications
      field :mark_notification_subject_as_read, mutation: Mutations::MarkNotificationSubjectAsRead
      field :mark_notification_as_done, mutation: Mutations::MarkNotificationAsDone
      field :mark_notifications_as_done, mutation: Mutations::MarkNotificationsAsDone
      field :mark_notification_as_undone, mutation: Mutations::MarkNotificationAsUndone
      field :mark_notifications_as_undone, mutation: Mutations::MarkNotificationsAsUndone
      field :mark_notification_as_unread, mutation: Mutations::MarkNotificationAsUnread
      field :mark_notifications_as_unread, mutation: Mutations::MarkNotificationsAsUnread
      field :mark_notification_as_read, mutation: Mutations::MarkNotificationAsRead
      field :mark_notifications_as_read, mutation: Mutations::MarkNotificationsAsRead
      field :create_saved_notification_thread, mutation: Mutations::CreateSavedNotificationThread
      field :delete_saved_notification_thread, mutation: Mutations::DeleteSavedNotificationThread
      field :update_notification_settings, mutation: Mutations::UpdateNotificationSettings
      field :update_notification_view_preference, mutation: Mutations::UpdateNotificationViewPreference
      field :unsubscribe_from_notifications, mutation: Mutations::UnsubscribeFromNotifications

      # Mobile Notifications
      field :add_mobile_device_token, mutation: Mutations::AddMobileDeviceToken
      field :create_mobile_push_notification_schedules, mutation: Mutations::CreateMobilePushNotificationSchedules
      field :delete_mobile_device_token, mutation: Mutations::DeleteMobileDeviceToken
      field :delete_mobile_push_notification_schedule, mutation: Mutations::DeleteMobilePushNotificationSchedule
      field :update_mobile_push_notification_schedules, mutation: Mutations::UpdateMobilePushNotificationSchedules
      field :update_mobile_push_notification_settings, mutation: Mutations::UpdateMobilePushNotificationSettings

      # Mobile auth (2FA, account recovery)
      field :add_mobile_device_public_key, mutation: Mutations::AddMobileDevicePublicKey
      field :delete_mobile_device_public_key, mutation: Mutations::DeleteMobileDevicePublicKey
      field :approve_mobile_auth_device_request, mutation: Mutations::ApproveMobileAuthDeviceRequest
      field :reject_mobile_auth_device_request, mutation: Mutations::RejectMobileAuthDeviceRequest

      # Check suites!
      field :create_check_suite, mutation: Mutations::CreateCheckSuite
      field :rerequest_check_suite, mutation: Mutations::RerequestCheckSuite
      field :update_check_suite_preferences, mutation: Mutations::UpdateCheckSuitePreferences
      field :update_check_suite, mutation: Mutations::UpdateCheckSuite
      field :create_check_run, mutation: Mutations::CreateCheckRun
      field :update_check_run, mutation: Mutations::UpdateCheckRun

      # Actions
      field :reuse_previous_workflow_run, mutation: Mutations::ReusePreviousWorkflowRun

      # Actions Mobile Integration
      field :create_completed_workflow_logs_access, mutation: Mutations::CreateCompletedWorkflowLogsAccess
      field :rerun_check_suite_mobile, mutation: Mutations::RerunCheckSuiteMobile
      field :rerun_check_run_mobile, mutation: Mutations::RerunCheckRunMobile
      field :cancel_workflow_run, mutation: Mutations::CancelWorkflowRun
      field :dispatch_workflow_run, mutation: Mutations::DispatchWorkflowRun

      # Gists
      # field :update_gist, mutation: Mutations::UpdateGist
      # If you are adding the update_gist mutation, please include
      # the following in your mutation.
      #
      # ```ruby
      # previous_gist_snapshot = pre_updated_gist.gist_snapshot
      # # update happens
      # updated_gist.instrument_hydro_update_event(actor: current_user, previous_gist_snapshot: previous_gist_snapshot)
      # ```
      #
      # For more details, read through this pr:
      # https://github.com/github/github/pull/102597
      # and this pr:
      # https://github.com/github/github/pull/169852

      # Projects
      field :create_project, mutation: Mutations::CreateProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :update_project, mutation: Mutations::UpdateProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :delete_project, mutation: Mutations::DeleteProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :clone_project, mutation: Mutations::CloneProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :import_project, mutation: Mutations::ImportProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :add_project_column, mutation: Mutations::AddProjectColumn, deprecated: Helpers::ProjectDeprecation::Notice
      field :move_project_column, mutation: Mutations::MoveProjectColumn, deprecated: Helpers::ProjectDeprecation::Notice
      field :update_project_column, mutation: Mutations::UpdateProjectColumn, deprecated: Helpers::ProjectDeprecation::Notice
      field :delete_project_column, mutation: Mutations::DeleteProjectColumn, deprecated: Helpers::ProjectDeprecation::Notice
      field :add_project_card, mutation: Mutations::AddProjectCard, deprecated: Helpers::ProjectDeprecation::Notice
      field :update_project_card, mutation: Mutations::UpdateProjectCard, deprecated: Helpers::ProjectDeprecation::Notice
      field :move_project_card, mutation: Mutations::MoveProjectCard, deprecated: Helpers::ProjectDeprecation::Notice
      field :archive_project_card, mutation: Mutations::ArchiveProjectCard, deprecated: Helpers::ProjectDeprecation::Notice
      field :unarchive_project_card, mutation: Mutations::UnarchiveProjectCard, deprecated: Helpers::ProjectDeprecation::Notice
      field :delete_project_card, mutation: Mutations::DeleteProjectCard, deprecated: Helpers::ProjectDeprecation::Notice
      field :add_project_workflow, mutation: Mutations::AddProjectWorkflow, deprecated: Helpers::ProjectDeprecation::Notice
      field :update_project_workflow, mutation: Mutations::UpdateProjectWorkflow, deprecated: Helpers::ProjectDeprecation::Notice
      field :delete_project_workflow, mutation: Mutations::DeleteProjectWorkflow, deprecated: Helpers::ProjectDeprecation::Notice
      field :add_project_collaborator, mutation: Mutations::AddProjectCollaborator, deprecated: Helpers::ProjectDeprecation::Notice
      field :update_project_collaborator, mutation: Mutations::UpdateProjectCollaborator, deprecated: Helpers::ProjectDeprecation::Notice
      field :remove_project_collaborator, mutation: Mutations::RemoveProjectCollaborator, deprecated: Helpers::ProjectDeprecation::Notice
      field :link_repository_to_project, mutation: Mutations::LinkRepositoryToProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :unlink_repository_from_project, mutation: Mutations::UnlinkRepositoryFromProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :convert_project_card_note_to_issue, mutation: Mutations::ConvertProjectCardNoteToIssue, deprecated: Helpers::ProjectDeprecation::Notice

      # Project Next aka. Memex
      field :update_project_next, mutation: Mutations::UpdateProjectNext
      field :add_project_next_item, mutation: Mutations::AddProjectNextItem
      field :add_project_draft_issue, mutation: Mutations::AddProjectDraftIssue
      field :delete_project_next_item, mutation: Mutations::DeleteProjectNextItem
      field :update_project_next_item_field, mutation: Mutations::UpdateProjectNextItemField
      field :update_project_draft_issue, mutation: Mutations::UpdateProjectDraftIssue

      # ProjectV2 aka. Memex
      field :create_project_v2, mutation: Mutations::CreateProjectV2
      field :update_project_v2, mutation: Mutations::UpdateProjectV2
      field :copy_project_v2, mutation: Mutations::CopyProjectV2
      field :delete_project_v2, mutation: Mutations::DeleteProjectV2
      field :create_project_v2_field, mutation: Mutations::CreateProjectV2Field
      field :update_project_v2_field, mutation: Mutations::UpdateProjectV2Field
      field :delete_project_v2_field, mutation: Mutations::DeleteProjectV2Field
      field :add_project_v2_item_by_id, mutation: Mutations::AddProjectV2ItemById
      field :add_project_v2_draft_issue, mutation: Mutations::AddProjectV2DraftIssue
      field :delete_project_v2_item, mutation: Mutations::DeleteProjectV2Item
      field :update_project_v2_item_field_value, mutation: Mutations::UpdateProjectV2ItemFieldValue
      field :clear_project_v2_item_field_value, mutation: Mutations::ClearProjectV2ItemFieldValue
      field :update_project_v2_draft_issue, mutation: Mutations::UpdateProjectV2DraftIssue
      field :update_project_v2_item_position, mutation: Mutations::UpdateProjectV2ItemPosition
      field :link_project_v2_to_repository, mutation: Mutations::LinkProjectV2ToRepository
      field :unlink_project_v2_from_repository, mutation: Mutations::UnlinkProjectV2FromRepository
      field :archive_project_v2_item, mutation: Mutations::ArchiveProjectV2Item
      field :unarchive_project_v2_item, mutation: Mutations::UnarchiveProjectV2Item
      field :link_project_v2_to_team, mutation: Mutations::LinkProjectV2ToTeam
      field :unlink_project_v2_from_team, mutation: Mutations::UnlinkProjectV2FromTeam
      field :create_project_v2_status_update, mutation: Mutations::CreateProjectV2StatusUpdate
      field :delete_project_v2_status_update, mutation: Mutations::DeleteProjectV2StatusUpdate
      field :update_project_v2_status_update, mutation: Mutations::UpdateProjectV2StatusUpdate
      field :delete_project_v2_workflow, mutation: Mutations::DeleteProjectV2Workflow
      field :delete_project_v2_workflow_by_number, mutation: Mutations::DeleteProjectV2WorkflowByNumber
      field :mark_project_v2_as_template, mutation: Mutations::MarkProjectV2AsTemplate
      field :unmark_project_v2_as_template, mutation: Mutations::UnmarkProjectV2AsTemplate
      field :update_project_v2_collaborators, mutation: Mutations::UpdateProjectV2Collaborators
      field :update_project_v2_last_viewed, mutation: Mutations::UpdateProjectV2LastViewed
      field :convert_project_v2_draft_issue_item_to_issue, mutation: Mutations::ConvertProjectV2DraftIssueItemToIssue

      # Labels
      field :create_label, mutation: Mutations::CreateLabel
      field :delete_label, mutation: Mutations::DeleteLabel
      field :update_label, mutation: Mutations::UpdateLabel
      field :delete_label_by_name, mutation: Mutations::DeleteLabelByName
      field :update_label_by_name, mutation: Mutations::UpdateLabelByName

      # Milestones
      field :create_milestone, mutation: Mutations::CreateMilestone

      # Issues
      field :unmark_issue_as_duplicate, mutation: Mutations::UnmarkIssueAsDuplicate
      field :lock_lockable, mutation: Mutations::LockLockable
      field :unlock_lockable, mutation: Mutations::UnlockLockable
      field :add_assignees_to_assignable, mutation: Mutations::AddAssigneesToAssignable
      field :remove_assignees_from_assignable, mutation: Mutations::RemoveAssigneesFromAssignable
      field :replace_assignees_for_assignable, mutation: Mutations::ReplaceAssigneesForAssignable
      field :add_labels_to_labelable, mutation: Mutations::AddLabelsToLabelable
      field :add_or_create_labels_to_labelable, mutation: Mutations::AddOrCreateLabelsToLabelable
      field :create_issue, mutation: Mutations::CreateIssue
      field :clear_labels_from_labelable, mutation: Mutations::ClearLabelsFromLabelable
      field :remove_labels_from_labelable, mutation: Mutations::RemoveLabelsFromLabelable
      field :replace_labels_for_labelable, mutation: Mutations::ReplaceLabelsForLabelable
      field :set_labels_for_labelable, mutation: Mutations::SetLabelsForLabelable
      field :close_issue, mutation: Mutations::CloseIssue
      field :reopen_issue, mutation: Mutations::ReopenIssue
      field :transfer_issue, mutation: Mutations::TransferIssue
      field :delete_issue_comment, mutation: Mutations::DeleteIssueComment
      field :update_issue, mutation: Mutations::UpdateIssue
      field :delete_issue, mutation: Mutations::DeleteIssue
      field :pin_issue, mutation: Mutations::PinIssue
      field :unpin_issue, mutation: Mutations::UnpinIssue
      field :prioritize_pinned_issues, mutation: Mutations::PrioritizePinnedIssues
      field :link_issue_or_pull_request, mutation: Mutations::LinkIssueOrPullRequest
      field :link_branches, mutation: Mutations::LinkBranches
      field :create_linked_branch, mutation: Mutations::CreateLinkedBranch
      field :delete_linked_branch, mutation: Mutations::DeleteLinkedBranch
      field :update_issues_bulk, mutation: Mutations::UpdateIssuesBulk
      field :update_issues_bulk_by_query, mutation: Mutations::UpdateIssuesBulkByQuery
      field :update_issue_issue_type, mutation: Mutations::UpdateIssueIssueType
      field :convert_issue_to_discussion, mutation: Mutations::ConvertIssueToDiscussion
      field :convert_checklist_item_to_sub_issue, mutation: Mutations::ConvertChecklistItemToSubIssue
      field :assign_app_to_issue, mutation: Mutations::AssignAppToIssue

      # User content edits
      field :delete_user_content_edit, mutation: Mutations::DeleteUserContentEdit

      # Issue Types
      field :delete_issue_type, mutation: Mutations::DeleteIssueType
      field :create_issue_type, mutation: Mutations::CreateIssueType
      field :update_issue_type, mutation: Mutations::UpdateIssueType

      # Sub Issues
      field :add_sub_issue, mutation: Mutations::AddSubIssue
      field :remove_sub_issue, mutation: Mutations::RemoveSubIssue
      field :reprioritize_sub_issue, mutation: Mutations::ReprioritizeSubIssue

      # Pull Request
      field :create_pull_request, mutation: Mutations::CreatePullRequest
      field :update_pull_request, mutation: Mutations::UpdatePullRequest
      field :update_pull_request_branch, mutation: Mutations::UpdatePullRequestBranch
      field :close_pull_request, mutation: Mutations::ClosePullRequest
      field :reopen_pull_request, mutation: Mutations::ReopenPullRequest
      field :mark_pull_request_ready_for_review, mutation: Mutations::MarkPullRequestReadyForReview
      field :mark_pull_request_latest_revision_as_seen, mutation: Mutations::MarkPullRequestLatestRevisionAsSeen
      field :merge_pull_request, mutation: Mutations::MergePullRequest
      field :mark_file_as_viewed, mutation: Mutations::MarkFileAsViewed
      field :unmark_file_as_viewed, mutation: Mutations::UnmarkFileAsViewed
      field :convert_pull_request_to_draft, mutation: Mutations::ConvertPullRequestToDraft
      field :enable_pull_request_auto_merge, mutation: Mutations::EnablePullRequestAutoMerge
      field :disable_pull_request_auto_merge, mutation: Mutations::DisablePullRequestAutoMerge
      field :approve_action_required_workflow_runs, mutation: Mutations::ApproveActionRequiredWorkflowRuns
      field :revert_pull_request, mutation: Mutations::RevertPullRequest
      field :delete_pull_request_head_ref, mutation: Mutations::DeletePullRequestHeadRef
      field :restore_pull_request_head_ref, mutation: Mutations::RestorePullRequestHeadRef

      # Pull Request Reviews
      field :add_pull_request_review, mutation: Mutations::AddPullRequestReview
      field :submit_pull_request_review, mutation: Mutations::SubmitPullRequestReview
      field :update_pull_request_review, mutation: Mutations::UpdatePullRequestReview
      field :dismiss_pull_request_review, mutation: Mutations::DismissPullRequestReview
      field :delete_pull_request_review, mutation: Mutations::DeletePullRequestReview

      field :resolve_review_thread, mutation: Mutations::ResolveReviewThread
      field :unresolve_review_thread, mutation: Mutations::UnresolveReviewThread
      field :resolve_pull_request_thread, mutation: Mutations::ResolvePullRequestThread
      field :unresolve_pull_request_thread, mutation: Mutations::UnresolvePullRequestThread

      # Pull Request Review Comments
      field :add_pull_request_review_comment, mutation: Mutations::AddPullRequestReviewComment
      field :update_pull_request_review_comment, mutation: Mutations::UpdatePullRequestReviewComment
      field :delete_pull_request_review_comment, mutation: Mutations::DeletePullRequestReviewComment

      # Pull Request Review Threads
      field :add_pull_request_review_thread, mutation: Mutations::AddPullRequestReviewThread
      field :add_pull_request_review_thread_reply, mutation: Mutations::AddPullRequestReviewThreadReply
      field :add_pull_request_thread_reply, mutation: Mutations::AddPullRequestThreadReply

      # Pull Request View Settings
      field :update_preferred_diff_view, mutation: Mutations::UpdatePreferredDiffView
      field :update_whitespace_preference, mutation: Mutations::UpdateWhitespacePreference

      # Merge queue
      field :enqueuePullRequest, mutation: Mutations::EnqueuePullRequest
      field :addPullRequestToMergeQueue, mutation: Mutations::AddPullRequestToMergeQueue
      field :dequeue_pull_request, mutation: Mutations::DequeuePullRequest
      field :removePullRequestFromMergeQueue, mutation: Mutations::RemovePullRequestFromMergeQueue
      field :lockMergeQueue, mutation: Mutations::LockMergeQueue
      field :mergeLockedMergeGroup, mutation: Mutations::MergeLockedMergeGroup
      field :unlockAndResetMergeGroup, mutation: Mutations::UnlockAndResetMergeGroup
      field :unlockMergeGroup, mutation: Mutations::UnlockMergeGroup
      field :forceClearMergeQueue, mutation: Mutations::ForceClearMergeQueue

      # IP allow list
      field :update_ip_allow_list_enabled_setting, mutation: Mutations::UpdateIpAllowListEnabledSetting
      field :update_ip_allow_list_for_installed_apps_enabled_setting, mutation: Mutations::UpdateIpAllowListForInstalledAppsEnabledSetting
      field :create_ip_allow_list_entry, mutation: Mutations::CreateIpAllowListEntry
      field :update_ip_allow_list_entry, mutation: Mutations::UpdateIpAllowListEntry
      field :delete_ip_allow_list_entry, mutation: Mutations::DeleteIpAllowListEntry

      # Enterprise accounts
      field :update_enterprise_profile, mutation: Mutations::UpdateEnterpriseProfile
      field :invite_enterprise_admin, mutation: Mutations::InviteEnterpriseAdmin
      field :invite_enterprise_member, mutation: Mutations::InviteEnterpriseMember
      field :accept_enterprise_administrator_invitation, mutation: Mutations::AcceptEnterpriseAdministratorInvitation
      field :accept_enterprise_member_invitation, mutation: Mutations::AcceptEnterpriseMemberInvitation
      field :access_user_namespace_repository, mutation: Mutations::AccessUserNamespaceRepository
      field :cancel_enterprise_admin_invitation, mutation: Mutations::CancelEnterpriseAdminInvitation
      field :cancel_enterprise_member_invitation, mutation: Mutations::CancelEnterpriseMemberInvitation
      field :complete_enterprise_organization_invitation, mutation: Mutations::CompleteEnterpriseOrganizationInvitation
      field :confirm_enterprise_organization_invitation, mutation: Mutations::ConfirmEnterpriseOrganizationInvitation
      field :add_enterprise_admin, mutation: Mutations::AddEnterpriseAdmin
      field :remove_enterprise_admin, mutation: Mutations::RemoveEnterpriseAdmin
      field :remove_enterprise_member, mutation: Mutations::RemoveEnterpriseMember
      field :invite_enterprise_organization, mutation: Mutations::InviteEnterpriseOrganization
      field :accept_enterprise_organization_invitation, mutation: Mutations::AcceptEnterpriseOrganizationInvitation
      field :cancel_enterprise_organization_invitation, mutation: Mutations::CancelEnterpriseOrganizationInvitation
      field :remove_enterprise_organization, mutation: Mutations::RemoveEnterpriseOrganization
      field :create_enterprise_organization, mutation: Mutations::CreateEnterpriseOrganization
      field :set_enterprise_identity_provider, mutation: Mutations::SetEnterpriseIdentityProvider
      field :set_enterprise_user_provisioning_settings, mutation: Mutations::SetEnterpriseUserProvisioningSettings
      field :remove_enterprise_identity_provider, mutation: Mutations::RemoveEnterpriseIdentityProvider
      field :regenerate_enterprise_identity_provider_recovery_codes, mutation: Mutations::RegenerateEnterpriseIdentityProviderRecoveryCodes
      field :transfer_enterprise_organization, mutation: Mutations::TransferEnterpriseOrganization
      field :update_enterprise_members_can_create_repositories_setting, mutation: Mutations::UpdateEnterpriseMembersCanCreateRepositoriesSetting
      field :update_enterprise_allow_private_repository_forking_setting, mutation: Mutations::UpdateEnterpriseAllowPrivateRepositoryForkingSetting
      field :update_enterprise_default_repository_permission_setting, mutation: Mutations::UpdateEnterpriseDefaultRepositoryPermissionSetting
      field :update_enterprise_team_discussions_setting, mutation: Mutations::UpdateEnterpriseTeamDiscussionsSetting
      field :update_enterprise_organization_projects_setting, mutation: Mutations::UpdateEnterpriseOrganizationProjectsSetting
      field :update_enterprise_repository_projects_setting, mutation: Mutations::UpdateEnterpriseRepositoryProjectsSetting
      field :update_enterprise_members_can_change_repository_visibility_setting, mutation: Mutations::UpdateEnterpriseMembersCanChangeRepositoryVisibilitySetting
      field :update_enterprise_members_can_invite_collaborators_setting, mutation: Mutations::UpdateEnterpriseMembersCanInviteCollaboratorsSetting
      field :update_enterprise_members_can_delete_repositories_setting, mutation: Mutations::UpdateEnterpriseMembersCanDeleteRepositoriesSetting
      field :update_enterprise_members_can_make_purchases_setting, mutation: Mutations::UpdateEnterpriseMembersCanMakePurchasesSetting
      field :update_enterprise_two_factor_authentication_required_setting, mutation: Mutations::UpdateEnterpriseTwoFactorAuthenticationRequiredSetting
      field :update_enterprise_two_factor_authentication_disallowed_methods_setting, mutation: Mutations::UpdateEnterpriseTwoFactorAuthenticationDisallowedMethodsSetting
      field :update_enterprise_members_can_update_protected_branches_setting, mutation: Mutations::UpdateEnterpriseMembersCanUpdateProtectedBranchesSetting
      field :update_enterprise_members_can_delete_issues_setting, mutation: Mutations::UpdateEnterpriseMembersCanDeleteIssuesSetting
      field :update_enterprise_members_can_view_dependency_insights_setting, mutation: Mutations::UpdateEnterpriseMembersCanViewDependencyInsightsSetting
      field :update_enterprise_owner_organization_role, mutation: Mutations::UpdateEnterpriseOwnerOrganizationRole
      field :update_enterprise_administrator_role, mutation: Mutations::UpdateEnterpriseAdministratorRole
      field :add_enterprise_support_entitlement, mutation: Mutations::AddEnterpriseSupportEntitlement
      field :remove_enterprise_support_entitlement, mutation: Mutations::RemoveEnterpriseSupportEntitlement
      field :add_enterprise_organization_member, mutation: Mutations::AddEnterpriseOrganizationMember
      field :update_enterprise_deploy_key_setting, mutation: Mutations::UpdateEnterpriseDeployKeySetting

      # Verifiable domains
      field :add_verifiable_domain, mutation: Mutations::AddVerifiableDomain
      field :delete_verifiable_domain, mutation: Mutations::DeleteVerifiableDomain
      field :regenerate_verifiable_domain_token, mutation: Mutations::RegenerateVerifiableDomainToken
      field :verify_verifiable_domain, mutation: Mutations::VerifyVerifiableDomain
      field :approve_verifiable_domain, mutation: Mutations::ApproveVerifiableDomain
      field :update_notification_restriction_setting, mutation: Mutations::UpdateNotificationRestrictionSetting

      # Organization
      field :remove_outside_collaborator, mutation: Mutations::RemoveOutsideCollaborator
      field :invite_to_organization, mutation: Mutations::InviteToOrganization
      field :update_organization_allow_private_repository_forking_setting, mutation: Mutations::UpdateOrganizationAllowPrivateRepositoryForkingSetting
      field :update_organization_web_commit_signoff_setting, mutation: Mutations::UpdateOrganizationWebCommitSignoffSetting

      # Organization moderation
      field :block_user_from_organization, mutation: Mutations::BlockUserFromOrganization
      field :unblock_user_from_organization, mutation: Mutations::UnblockUserFromOrganization

      # Organization following
      field :follow_organization, mutation: Mutations::FollowOrganization
      field :unfollow_organization, mutation: Mutations::UnfollowOrganization

      # Review Requests
      field :request_reviews, mutation: Mutations::RequestReviews
      field :request_review_from_copilot, mutation: Mutations::RequestReviewFromCopilot
      field :provide_copilot_code_review_feedback, mutation: Mutations::ProvideCopilotCodeReviewFeedback

      # Packages
      field :delete_package_version, mutation: Mutations::DeletePackageVersion
      field :increment_registry_package_download_count, mutation: Mutations::IncrementRegistryPackageDownloadCount
      field :create_package_version, mutation: Mutations::CreatePackageVersion
      field :update_package_version, mutation: Mutations::UpdatePackageVersion
      field :create_package_file, mutation: Mutations::CreatePackageFile
      field :update_package_file, mutation: Mutations::UpdatePackageFile
      field :create_package_version_metadata, mutation: Mutations::CreatePackageVersionMetadata
      field :add_package_tag, mutation: Mutations::AddPackageTag
      field :delete_package_tag, mutation: Mutations::DeletePackageTag

      # Repository
      field :transfer_repository, mutation: Mutations::TransferRepository
      field :create_commit_on_branch, mutation: Mutations::CreateCommitOnBranch
      field :clone_template_repository, mutation: Mutations::CloneTemplateRepository
      field :create_repository, mutation: Mutations::CreateRepository
      field :update_repository, mutation: Mutations::UpdateRepository
      field :create_ref, mutation: Mutations::CreateRef
      field :update_ref, mutation: Mutations::UpdateRef
      field :delete_ref, mutation: Mutations::DeleteRef
      field :update_refs, mutation: Mutations::UpdateRefs
      field :merge_branch, mutation: Mutations::MergeBranch
      field :updateRepositoryWebCommitSignoffSetting, mutation: Mutations::UpdateRepositoryWebCommitSignoffSetting

      # Spamurai
      field :classify_accounts_as_hammy, mutation: Mutations::ClassifyAccountsAsHammy
      field :classify_accounts_as_spammy, mutation: Mutations::ClassifyAccountsAsSpammy
      field :clear_account_classifications, mutation: Mutations::ClearAccountClassifications
      field :block_actions, mutation: Mutations::BlockActions
      field :suspend_accounts, mutation: Mutations::SuspendAccounts
      field :unsuspend_accounts, mutation: Mutations::UnsuspendAccounts
      field :set_has_used_anonymizing_proxy, mutation: Mutations::SetHasUsedAnonymizingProxy

      # Security
      field :reset_passwords, mutation: Mutations::ResetPasswords
      field :resolve_security_incident, mutation: Mutations::ResolveSecurityIncident

      # Sponsors
      field :create_sponsorship, mutation: Mutations::CreateSponsorship
      field :create_sponsorship_newsletter, mutation: Mutations::CreateSponsorshipNewsletter
      field :create_sponsorships, mutation: Mutations::CreateSponsorships
      field :cancel_sponsorship, mutation: Mutations::CancelSponsorship
      field :update_sponsorship_preferences, mutation: Mutations::UpdateSponsorshipPreferences
      field :create_sponsors_tier, mutation: Mutations::CreateSponsorsTier
      field :publish_sponsors_tier, mutation: Mutations::PublishSponsorsTier
      field :retire_sponsors_tier, mutation: Mutations::RetireSponsorsTier
      field :create_sponsors_listing, mutation: Mutations::CreateSponsorsListing
      field :update_patreon_sponsorability, mutation: Mutations::UpdatePatreonSponsorability

      # Stars
      field :add_star, mutation: Mutations::AddStar
      field :remove_star, mutation: Mutations::RemoveStar

      # Staffnotes
      field :add_staff_note, mutation: Mutations::AddStaffNote
      field :update_staff_note, mutation: Mutations::UpdateStaffNote

      # Stafftools
      field :block_models, mutation: Mutations::BlockModels
      field :block_copilot, mutation: Mutations::BlockCopilot
      field :disable_repositories, mutation: Mutations::DisableRepositories
      field :block_accounts_action_invocation, mutation: Mutations::BlockAccountsActionInvocation
      field :unblock_accounts_action_invocation, mutation: Mutations::UnblockAccountsActionInvocation
      field :detach_repositories, mutation: Mutations::DetachRepositories
      field :unlock_private_audit_log, mutation: Mutations::UnlockPrivateAuditLog
      field :apply_content_warnings, mutation: Mutations::ApplyContentWarnings
      field :remove_content_warnings, mutation: Mutations::RemoveContentWarnings
      field :staff_archive_repository, mutation: Mutations::StaffArchiveRepository
      field :staff_unarchive_repository, mutation: Mutations::StaffUnarchiveRepository
      field :block_payment_method_and_suspend_users_by_card_fingerprint, mutation: Mutations::BlockPaymentMethodAndSuspendUsersByCardFingerprint
      field :staff_delete_repositories, mutation: Mutations::StaffDeleteRepositories
      field :staff_delete_repository_files_by_user, mutation: Mutations::StaffDeleteRepositoryFilesByUser
      field :staff_delete_user_assets_by_user, mutation: Mutations::StaffDeleteUserAssetsByUser

      # Topics
      field :accept_topic_suggestion, mutation: Mutations::AcceptTopicSuggestion
      field :decline_topic_suggestion, mutation: Mutations::DeclineTopicSuggestion
      field :update_topics, mutation: Mutations::UpdateTopics
      field :update_topic, mutation: Mutations::UpdateTopic

      # Teams
      field :create_team, mutation: Mutations::CreateTeam
      field :update_team, mutation: Mutations::UpdateTeam
      field :delete_team, mutation: Mutations::DeleteTeam
      field :update_team_review_assignment, mutation: Mutations::UpdateTeamReviewAssignment

      # TeamDiscussion
      field :create_team_discussion, mutation: Mutations::CreateTeamDiscussion
      field :update_team_discussion, mutation: Mutations::UpdateTeamDiscussion
      field :delete_team_discussion, mutation: Mutations::DeleteTeamDiscussion

      # TeamDiscussionComment
      field :create_team_discussion_comment, mutation: Mutations::CreateTeamDiscussionComment
      field :update_team_discussion_comment, mutation: Mutations::UpdateTeamDiscussionComment
      field :delete_team_discussion_comment, mutation: Mutations::DeleteTeamDiscussionComment

      # Team Member
      field :add_team_member, mutation: Mutations::AddTeamMember
      field :update_team_member, mutation: Mutations::UpdateTeamMember
      field :remove_team_member, mutation: Mutations::RemoveTeamMember

      # Team Repository
      field :update_team_repository, mutation: Mutations::UpdateTeamRepository
      field :update_teams_repository, mutation: Mutations::UpdateTeamsRepository

      # Team Project
      field :add_team_project, mutation: Mutations::AddTeamProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :update_team_project, mutation: Mutations::UpdateTeamProject, deprecated: Helpers::ProjectDeprecation::Notice
      field :remove_team_project, mutation: Mutations::RemoveTeamProject, deprecated: Helpers::ProjectDeprecation::Notice

      # Team Change Parent Requests
      field :approve_pending_team_change_parent_request, mutation: Mutations::ApprovePendingTeamChangeParentRequest
      field :cancel_pending_team_change_parent_request, mutation: Mutations::CancelPendingTeamChangeParentRequest
      field :create_parent_initiated_team_change_parent_request, mutation: Mutations::CreateParentInitiatedTeamChangeParentRequest

      # Marketplace listing plans
      field :create_marketplace_listing_plan, mutation: Mutations::CreateMarketplaceListingPlan
      field :update_marketplace_listing_plan, mutation: Mutations::UpdateMarketplaceListingPlan
      field :delete_marketplace_listing_plan, mutation: Mutations::DeleteMarketplaceListingPlan
      field :retire_marketplace_listing_plan, mutation: Mutations::RetireMarketplaceListingPlan
      field :publish_marketplace_listing_plan, mutation: Mutations::PublishMarketplaceListingPlan

      # Marketplace listing screenshots
      field :update_marketplace_listing_screenshot, mutation: Mutations::UpdateMarketplaceListingScreenshot
      field :resequence_marketplace_listing_screenshot, mutation: Mutations::ResequenceMarketplaceListingScreenshot
      field :delete_marketplace_listing_screenshot, mutation: Mutations::DeleteMarketplaceListingScreenshot

      # Marketplace order previews
      field :update_marketplace_order_preview, mutation: Mutations::UpdateMarketplaceOrderPreview
      field :record_marketplace_retargeting_notifications, mutation: Mutations::RecordMarketplaceRetargetingNotifications

      # Import/Export
      field :start_import, mutation: Mutations::StartImport
      field :prepare_import, mutation: Mutations::PrepareImport
      field :add_import_mapping, mutation: Mutations::AddImportMapping
      field :perform_import, mutation: Mutations::PerformImport
      field :unlock_imported_repositories, mutation: Mutations::UnlockImportedRepositories
      field :create_attribution_invitation, mutation: Mutations::CreateAttributionInvitation
      field :reattribute_mannequin_to_user, mutation: Mutations::ReattributeMannequinToUser

      # Browser Stats
      field :report_browser_error, mutation: Mutations::ReportBrowserError

      # Features
      field :enable_beta_feature, mutation: Mutations::EnableBetaFeature
      field :disable_beta_feature, mutation: Mutations::DisableBetaFeature

      # ToggleableFeatures
      field :enroll_in_toggleable_feature, mutation: Mutations::EnrollInToggleableFeature
      field :unenroll_in_toggleable_feature, mutation: Mutations::UnenrollInToggleableFeature

      # Integration Category
      field :createIntegrationCategory, mutation: Mutations::CreateIntegrationCategory
      field :updateIntegrationCategory, mutation: Mutations::UpdateIntegrationCategory

      # Retired Namespaces
      field :retire_namespace, mutation: Mutations::RetireNamespace
      field :unretire_namespace, mutation: Mutations::UnretireNamespace

      # Deployments
      field :create_deployment, mutation: Mutations::CreateDeployment
      field :delete_deployment, mutation: Mutations::DeleteDeployment
      field :create_deployment_status, mutation: Mutations::CreateDeploymentStatus

      field :pin_environment,   mutation:  Mutations::PinEnvironment
      field :reorder_environment, mutation: Mutations::ReorderEnvironment
      field :create_environment, mutation: Mutations::CreateEnvironment
      field :update_environment, mutation: Mutations::UpdateEnvironment
      field :delete_environment, mutation: Mutations::DeleteEnvironment
      field :create_gate_request, mutation: Mutations::CreateGateRequest
      field :approve_deployments, mutation: Mutations::ApproveDeployments
      field :reject_deployments, mutation: Mutations::RejectDeployments

      field :createBranchProtectionRule, mutation: Mutations::CreateBranchProtectionRule
      field :updateBranchProtectionRule, mutation: Mutations::UpdateBranchProtectionRule
      field :deleteBranchProtectionRule, mutation: Mutations::DeleteBranchProtectionRule

      field :createRepositoryRuleset, mutation: Mutations::CreateRepositoryRuleset
      field :updateRepositoryRuleset, mutation: Mutations::UpdateRepositoryRuleset
      field :deleteRepositoryRuleset, mutation: Mutations::DeleteRepositoryRuleset

      # Interaction limits
      field :set_repository_interaction_limit, mutation: Mutations::SetRepositoryInteractionLimit
      field :set_user_interaction_limit, mutation: Mutations::SetUserInteractionLimit
      field :set_organization_interaction_limit, mutation: Mutations::SetOrganizationInteractionLimit

      # Suggested changes
      field :apply_suggested_changes, mutation: Mutations::ApplySuggestedChanges
      field :apply_mobile_suggested_changes, mutation: Mutations::ApplyMobileSuggestedChanges

      # Users
      field :change_user_status, mutation: Mutations::ChangeUserStatus
      field :reorder_profile_pins, mutation: Mutations::ReorderProfilePins
      field :set_profile_pins, mutation: Mutations::SetProfilePins
      field :dismiss_notice, mutation: Mutations::DismissNotice
      field :dismiss_repository_notice, mutation: Mutations::DismissRepositoryNotice
      field :follow_user, mutation: Mutations::FollowUser
      field :unfollow_user, mutation: Mutations::UnfollowUser
      field :block_user, mutation: Mutations::BlockUser
      field :unblock_user, mutation: Mutations::UnblockUser
      field :create_user_list, mutation: Mutations::CreateUserList
      field :update_user_list, mutation: Mutations::UpdateUserList
      field :delete_user_list, mutation: Mutations::DeleteUserList
      field :update_user_lists_for_item, mutation: Mutations::UpdateUserListsForItem

      # Mobile
      field :mobile_events_update, mutation: Mutations::MobileEventsUpdate
      field :update_user_mobile_time_zone, mutation: Mutations::UpdateUserMobileTimeZone
      field :create_mobile_subscription, mutation: Mutations::CreateMobileSubscription
      field :create_apple_iap_subscriptions, mutation: Mutations::CreateAppleIapSubscriptions
      field :create_google_iap_subscription, mutation: Mutations::CreateGoogleIapSubscription
      field :subscribe_to_copilot_limited, mutation: Mutations::SubscribeToCopilotLimited

      # Dashboard
      field :update_user_dashboard_nav_links, mutation: Mutations::UpdateUserDashboardNavLinks
      field :create_user_dashboard_pin, mutation: Mutations::CreateUserDashboardPin
      field :delete_user_dashboard_pin, mutation: Mutations::DeleteUserDashboardPin
      field :update_user_dashboard_pins, mutation: Mutations::UpdateUserDashboardPins
      field :set_user_dashboard_pins, mutation: Mutations::SetUserDashboardPins
      field :reorder_dashboard_pins, mutation: Mutations::ReorderDashboardPins

      # Dashboard search shortcuts
      field :set_dashboard_search_shortcuts, mutation: Mutations::SetDashboardSearchShortcuts
      field :create_dashboard_search_shortcut, mutation: Mutations::CreateDashboardSearchShortcut
      field :move_dashboard_search_shortcut, mutation: Mutations::MoveDashboardSearchShortcut
      field :remove_dashboard_search_shortcut, mutation: Mutations::RemoveDashboardSearchShortcut
      field :update_dashboard_search_shortcut, mutation: Mutations::UpdateDashboardSearchShortcut
      field :update_dashboard_selected_teams, mutation: Mutations::UpdateDashboardSelectedTeams

      # Saved collections
      field :create_saved_collection, mutation: Mutations::CreateSavedCollection

      # Saved views
      field :create_saved_view, mutation: Mutations::CreateSavedView
      field :update_saved_view, mutation: Mutations::UpdateSavedView
      field :delete_saved_view, mutation: Mutations::DeleteSavedView

      # Team dashboard search shortcuts
      field :create_team_dashboard_search_shortcut, mutation: Mutations::CreateTeamDashboardSearchShortcut
      field :update_team_dashboard_search_shortcut, mutation: Mutations::UpdateTeamDashboardSearchShortcut
      field :remove_team_dashboard_search_shortcut, mutation: Mutations::RemoveTeamDashboardSearchShortcut

      # Dependabot
      field :mark_repository_dependency_update_complete, mutation: Mutations::MarkRepositoryDependencyUpdateComplete
      field :mark_repository_dependency_update_errored, mutation: Mutations::MarkRepositoryDependencyUpdateErrored

      # Repository archiving
      field :archive_repository, mutation: Mutations::ArchiveRepository
      field :unarchive_repository, mutation: Mutations::UnarchiveRepository

      # Discussions
      field :add_upvote, mutation: Mutations::AddUpvote
      field :remove_upvote, mutation: Mutations::RemoveUpvote
      field :create_discussion, mutation: Mutations::CreateDiscussion
      field :delete_discussion, mutation: Mutations::DeleteDiscussion
      field :update_discussion, mutation: Mutations::UpdateDiscussion
      field :add_discussion_comment, mutation: Mutations::AddDiscussionComment
      field :delete_discussion_comment, mutation: Mutations::DeleteDiscussionComment
      field :update_discussion_comment, mutation: Mutations::UpdateDiscussionComment
      field :mark_discussion_comment_as_answer, mutation: Mutations::MarkDiscussionCommentAsAnswer
      field :unmark_discussion_comment_as_answer, mutation: Mutations::UnmarkDiscussionCommentAsAnswer
      field :add_discussion_poll_vote, mutation: Mutations::AddDiscussionPollVote
      field :close_discussion, mutation: Mutations::CloseDiscussion
      field :reopen_discussion, mutation: Mutations::ReopenDiscussion

      # Octoshift
      field :create_migration_source, mutation: Mutations::CreateMigrationSource
      field :start_repository_migration, mutation: Mutations::StartRepositoryMigration
      field :grant_migrator_role, mutation: Mutations::GrantMigratorRole
      field :grant_enterprise_organizations_migrator_role, mutation: Mutations::GrantEnterpriseOrganizationsMigratorRole
      field :revoke_migrator_role, mutation: Mutations::RevokeMigratorRole
      field :revoke_enterprise_organizations_migrator_role, mutation: Mutations::RevokeEnterpriseOrganizationsMigratorRole
      field :abort_queued_migrations, mutation: Mutations::AbortQueuedMigrations
      field :abort_repository_migration, mutation: Mutations::AbortRepositoryMigration
      field :start_organization_migration, mutation: Mutations::StartOrganizationMigration
      field :delete_migration_archive, mutation: Mutations::DeleteMigrationArchive

      # RepositoryVulnerabilityAlert
      field :dismiss_repository_vulnerability_alert, mutation: Mutations::DismissRepositoryVulnerabilityAlert

      # Conduit
      field :set_dashboard_feed_filters, mutation: Mutations::SetDashboardFeedFilters
      field :create_user_disinterest, mutation: Mutations::CreateUserDisinterest
      field :undo_user_disinterest, mutation: Mutations::UndoUserDisinterest

      # Trade Screening
      field :set_trade_screening_status, mutation: Mutations::SetTradeScreeningStatus
      field :sdn_suspend, mutation: Mutations::SdnSuspend
      field :sdn_unsuspend, mutation: Mutations::SdnUnsuspend
      field :sdn_request_screen, mutation: Mutations::SdnRequestScreen
    end
  end
end
