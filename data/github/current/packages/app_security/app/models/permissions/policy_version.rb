# typed: true
# frozen_string_literal: true

module Permissions
  class PolicyVersion
    extend T::Sig

    SubjectAgnosticPolicyVersions = T.type_alias { T::Hash[Symbol, Integer] }
    SubjectSpecificPolicyVersions = T.type_alias { T::Hash[Symbol, T::Hash[Symbol, Integer]] }

    # These are the versions of policies that are matched in `authzd` by action name (the keys of this hash) alone.
    #
    # If a key appears in this hash, it should not also appear in `SUBJECT_SPECIFIC_POLICY_VERSIONS`.
    #
    # Extending this hash is preferred to extending `SUBJECT_SPECIFIC_POLICY_VERSIONS`, because pinning versions via
    # this mechanism is simpler.
    SUBJECT_AGNOSTIC_POLICY_VERSIONS = T.let({
        # Please keep alphabetic order.
        access_ip_allowlist_protected_content: 1,
        add_assignee:                          1,
        add_label:                             1,
        admin_project:                         4,
        bypass_branch_protection:              2,
        close_pull_request:                    1,
        close_issue:                           1,
        create_discussion:                     1,
        create_discussion_announcement:        1,
        create_discussion_category:            2,
        delete_discussion:                     2,
        edit_discussion_category:              3,
        edit_repo_metadata:                    2,
        edit_repo_protections:                 2,
        github_app_create_tag:                 2,
        github_app_creates_team_posts:         2,
        github_app_delete_tag:                 2,
        github_app_deletes_org_owned_issue:    2,
        github_app_deletes_user_owned_issue:   2,
        github_app_reads_org_project:          2,
        github_app_writes_org_project:         2,
        grant_manage_organization_apps:        1,
        grant_manage_app:                      1,
        grantable_manage_organization_apps:    1,
        grantable_manage_app:                  1,
        installation_access_org_webhooks:      2,
        installation_discussions_write:        2,
        installation_issue_write:              2,
        installation_manage_discussion_comment: 2,
        installation_manages_org_self_hosted_runners: 2,
        installation_pull_request_write:       2,
        installation_read_discussion_resources: 2,
        installation_read_org_audit_logs:      2,
        installation_repository_administration: 2,
        manage_all_apps:                       1,
        manage_app:                            1,
        manage_organization_ref_rules:         1,
        manage_topics:                         1,
        manage_settings_wiki:                  2,
        manage_settings_projects:              2,
        manage_settings_pages:                 2,
        manage_settings_merge_types:           2,
        manage_deploy_keys:                    2,
        manage_discussion_spotlights:          2,
        mark_as_duplicate:                     1,
        programmatic_actor_manage_deploy_keys: 2,
        programmatic_actor_manage_org_custom_properties: 2,
        programmatic_actor_read_repository_resources: 2,
        programmatic_actor_write_repository_custom_properties: 2,
        programmatic_actor_write_repository_resources: 2,
        push_protected_branch:                 2,
        read_audit_logs:                       2,
        read_project:                          5,
        receive_notification:                  1,
        reopen_issue:                          1,
        reopen_pull_request:                   1,
        request_pr_review:                     2,
        run_org_migration:                     2,
        set_interaction_limits:                2,
        set_milestone:                         1,
        set_social_preview:                    2,
        setup_issue_template:                  1,
        star_repo:                             1,
        unmark_as_duplicate:                   1,
        view_dependabot_alerts:                3,
        resolve_dependabot_alerts:             3,
        view_secret_scanning_alerts:           3,
        resolve_secret_scanning_alerts:        3,
        view_hook_deliveries:                  2,
        write_project:                         4,
      }.freeze,
      SubjectAgnosticPolicyVersions
    )


    # These are versions of policies that are matched in `authzd` by both action name and subject type (the keys in
    # this nested hash).
    #
    # If a key appears in this hash, it should not also appear in `SUBJECT_AGNOSTIC_POLICY_VERSIONS`.
    #
    # Extending this hash is discouraged because it is more complicated than the alternative
    # available through `SUBJECT_AGNOSTIC_POLICY_VERSIONS``.
    SUBJECT_SPECIFIC_POLICY_VERSIONS = T.let(
      {
        # Please keep alphabetic order.
        view_live_update: {
          memex_project: 5,
        },
      }.freeze,
      SubjectSpecificPolicyVersions
    )

    LATEST = -1
    VERSION_ATTRIBUTE = T.let("version".freeze, String)
    InvalidPolicyVersion = Class.new(Authzd::Error)

    # Returns the policy version to use for a particular action.
    #
    # @param action Either a single action name, or an array of them. The array form can only be used for policies
    #   that are matched by action name alone (i.e. those that appear in `SUBJECT_AGNOSTIC_POLICY_VERSIONS` above).
    # @param subject Optional authorization subject for use with policies that are matched by both action name and
    #   subject type (i.e those in `SUBJECT_SPECIFIC_POLICY_VERSIONS` above.)
    #
    # @raises InvalidPolicyVersion if given an array of actions that do not all share the same version.
    #
    # @returns a positive integer representing the pinned policy version for a particular action, or -1 to indicate
    #   that we should use the latest policy version defined in `authzd`.
    sig do
      params(
        action: T.any(T.any(String, Symbol), T::Array[T.any(String, Symbol)]),
        subject: T.nilable(Permissions::Attributes::Wrapper)
      )
      .returns(Integer)
    end
    def self.version_for(action:, subject: nil)
      if action.kind_of?(Array)
        result = T.unsafe(self).subject_agnostic_policy_versions.values_at(*action.map(&:to_sym)).uniq.compact
        raise InvalidPolicyVersion.new("action array with different versions found") if result.size > 1
        return result.fetch(0, LATEST)
      end

      if self.subject_specific_policy_versions.include?(action.to_sym) && subject.present?
        subject_type = subject.permissions_wrapper.subject_type&.underscore&.to_sym
        return self.subject_specific_policy_versions.dig(action.to_sym, subject_type) || LATEST
      end

      self.subject_agnostic_policy_versions.fetch(action.to_sym, LATEST)
    end

    sig { returns(SubjectAgnosticPolicyVersions) }
    def self.subject_agnostic_policy_versions
      SUBJECT_AGNOSTIC_POLICY_VERSIONS
    end

    sig { returns(SubjectSpecificPolicyVersions) }
    def self.subject_specific_policy_versions
      SUBJECT_SPECIFIC_POLICY_VERSIONS
    end
  end
end
