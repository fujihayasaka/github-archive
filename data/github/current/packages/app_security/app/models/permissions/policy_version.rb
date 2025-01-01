# typed: true
# frozen_string_literal: true

module Permissions
  class PolicyVersion

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
        add_assignee:                                    3,
        add_label:                                       3,
        add_milestone:                                   3,
        admin_package:                                   3,
        admin_project:                                   4,
        bypass_branch_protection:                        2,
        change_tag:                                      3,
        close_discussion:                                3,
        close_issue:                                     3,
        close_pull_request:                              3,
        create_discussion_announcement:                  3,
        create_discussion_category:                      2,
        create_discussion_comment:                       3,
        create_discussion:                               3,
        create_tag:                                      3,
        delete_discussion_comment:                       3,
        delete_discussion:                               3,
        delete_issue:                                    3,
        delete_tag:                                      3,
        edit_category_on_discussion:                     3,
        edit_discussion_category:                        3,
        edit_discussion_comment:                         3,
        edit_discussion:                                 3,
        edit_org_custom_properties_values:               3,
        edit_repo_custom_properties_values:              3,
        edit_repo_description:                           3,
        edit_repo_metadata:                              2,
        edit_repo_protections:                           2,
        grant_manage_app:                                1,
        grant_manage_organization_apps:                  1,
        grantable_manage_app:                            1,
        grantable_manage_organization_apps:              1,
        manage_all_apps:                                 1,
        manage_app:                                      1,
        manage_deploy_keys:                              3,
        manage_discussion_badges:                        3,
        manage_discussion_spotlights:                    2,
        manage_org_custom_properties_definitions:        3,
        manage_organization_actions_self_hosted_runners: 3,
        manage_organization_ref_rules:                   1,
        manage_organization_webhooks:                    3,
        manage_settings_discussions:                     3,
        manage_settings_merge_types:                     2,
        manage_settings_pages:                           2,
        manage_settings_projects:                        2,
        manage_settings_wiki:                            2,
        manage_topics:                                   3,
        mark_as_duplicate:                               1,
        push_protected_branch:                           3,
        read_audit_logs:                                 3,
        read_discussion_category:                        3,
        read_discussion_metadata:                        3,
        read_discussion:                                 3,
        read_organization_network_configurations:        3,
        read_organization_runner_custom_images:          3,
        read_package:                                    3,
        read_project:                                    6,
        read_repo_contents:                              3,
        read_repo_metadata:                              3,
        read_repo_pull_requests:                         3,
        read_repo_single_file:                           4,
        receive_notification:                            1,
        remove_assignee:                                 3,
        remove_label:                                    3,
        remove_milestone:                                3,
        reopen_discussion:                               3,
        reopen_issue:                                    3,
        reopen_pull_request:                             3,
        request_pr_review:                               3,
        resolve_dependabot_alerts:                       3,
        resolve_secret_scanning_alerts:                  3,
        run_org_migration:                               2,
        set_interaction_limits:                          3,
        set_milestone:                                   1,
        set_social_preview:                              2,
        star_repo:                                       1,
        toggle_discussion_answer:                        3,
        toggle_discussion_comment_minimize:              3,
        toggle_discussion_comment_reaction:              3,
        toggle_discussion_lock:                          3,
        toggle_discussion_reaction:                      3,
        unmark_as_duplicate:                             1,
        view_dependabot_alerts:                          3,
        view_hook_deliveries:                            2,
        view_secret_scanning_alerts:                     3,
        write_organization_network_configurations:       3,
        write_organization_runner_custom_images:         3,
        write_package:                                   3,
        write_project:                                   6,
        write_repo_contents:                             3,
        write_repo_pull_requests:                        3,
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
        check_any_permission: {
          business: 1,
          organization: 1,
        },
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
        raise InvalidPolicyVersion.new("callsites with an array as action, need to set their version in the context")
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
