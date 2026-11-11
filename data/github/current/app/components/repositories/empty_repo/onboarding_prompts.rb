# typed: true
# frozen_string_literal: true

# Single source of truth for the "empty repo" onboarding prompt cards (primary +
# secondary) rendered by `app/views/repositories/states/empty.html.erb` and
# emitted to github-ui via the code-view layout payload as `onboardingPrompts`.
#
# Encapsulates variant selection, copy, and resolved URLs so both the ERB and
# React rendering paths consume the same descriptors.
module Repositories
  module EmptyRepo
    class OnboardingPrompts
      include GitHub::Memoizer

      PAYLOAD_KEYS = %i[variant icon title description button_label href analytics feature_request].freeze
      PAYLOAD_KEY_RENAMES = {
        button_label: :buttonLabel,
        analytics: :analyticsEvent,
        feature_request: :featureRequest,
      }.freeze

      def initialize(repository:, current_user:, user_can_push:, copilot_user: nil)
        @repository = repository
        @current_user = current_user
        @user_can_push = user_can_push
        @copilot_user = copilot_user
      end

      # Returns the wire payload consumed by github-ui:
      #   { primary: { icon:, title:, description:, buttonLabel:, href: },
      #     secondary: { ... } }
      # Either slot may be omitted. Returns nil when the viewer can't push or
      # when neither slot is populated.
      def to_payload
        return nil unless @user_can_push

        payload = { primary: payload_for(primary_prompt), secondary: payload_for(secondary_prompt) }.compact
        payload.empty? ? nil : payload
      end

      # Returns a Hash descriptor for the primary (Copilot/Codespaces) card or
      # nil when no primary prompt should render.
      def primary_prompt
        return nil unless @user_can_push
        return nil if enterprise_or_emu?

        if show_copilot_organization_admin_prompt?
          copilot_org_admin_prompt
        elsif show_copilot_organization_member_prompt?
          copilot_org_member_prompt
        elsif show_copilot_individual_prompt?
          copilot_individual_prompt
        else
          codespaces_prompt
        end
      end

      # Returns a Hash descriptor for the secondary (invite / move / manage
      # access) card or nil when no secondary prompt should render.
      def secondary_prompt
        return nil unless @user_can_push
        return nil unless @repository

        if enterprise_or_emu?
          show_org_admin_only? ? org_admin_prompt : nil
        elsif @repository.in_organization?
          org_prompt
        elsif @repository.members_count >= 5
          move_to_org_prompt
        else
          user_default_prompt
        end
      end

      private

      def payload_for(prompt)
        return nil unless prompt

        prompt.slice(*PAYLOAD_KEYS).each_with_object({}) do |(key, value), out|
          wire_key = PAYLOAD_KEY_RENAMES[key] || key
          out[wire_key] = key == :icon ? value.to_s : value
        end
      end

      def routes
        Rails.application.routes.url_helpers
      end

      def enterprise_or_emu?
        GitHub.single_or_multi_tenant_enterprise? || !!@current_user&.is_enterprise_managed?
      end

      memoize def show_org_admin_only?
        enterprise_or_emu? &&
          !!@repository&.adminable_by?(@current_user) &&
          !!@repository&.in_organization? &&
          @repository&.members_count == 0
      end

      memoize def copilot_user
        return @copilot_user if @copilot_user
        @current_user ? Copilot::User.new(@current_user) : nil
      end

      memoize def repo_organization
        @repository&.organization
      end

      memoize def repo_owned_by_org?
        !!@repository&.in_organization?
      end

      memoize def eligible_for_raf_copilot_prompt?
        !repo_organization&.business
      end

      memoize def user_is_org_admin?
        return false unless repo_owned_by_org?
        !!repo_organization&.adminable_by?(@current_user)
      end

      memoize def free_copilot_access?
        return true if copilot_user&.has_free_access?
        return true if copilot_user&.can_signup_for_free?
        false
      end

      memoize def no_copilot_access?
        !copilot_user&.access_allowed?
      end

      memoize def user_part_of_org?
        !!@current_user&.member_or_billing_manager_for_any_organization?
      end

      memoize def eligible_raf_organization_copilot_prompt?
        return false unless MemberFeatureRequest::Feature::CopilotForBusiness.upsell_eligible?(
          requester: @current_user,
          request_entity: repo_organization,
        )

        org_admin_without_copilot = user_is_org_admin? && no_copilot_access?
        org_member_without_free_copilot = !user_is_org_admin? && !free_copilot_access?
        org_admin_without_copilot || org_member_without_free_copilot
      end

      memoize def show_copilot_organization_admin_prompt?
        eligible_for_raf_copilot_prompt? &&
          repo_owned_by_org? &&
          eligible_raf_organization_copilot_prompt? &&
          user_is_org_admin?
      end

      memoize def show_copilot_organization_member_prompt?
        eligible_for_raf_copilot_prompt? &&
          repo_owned_by_org? &&
          eligible_raf_organization_copilot_prompt? &&
          !user_is_org_admin?
      end

      memoize def copilot_for_business_member_feature_request
        org = repo_organization
        return nil unless @current_user && org

        billing_entity = org.adminable_by?(@current_user) ? org.business : org
        MemberFeatureRequest.find_request(
          @current_user,
          org,
          MemberFeatureRequest::Feature::CopilotForBusiness,
          billing_entity,
        )
      end

      def copilot_for_business_requested?
        !!copilot_for_business_member_feature_request&.requested?
      end

      def copilot_for_business_dismissed?
        !!copilot_for_business_member_feature_request&.dismissed?
      end

      def copilot_for_business_dismissed_at
        copilot_for_business_member_feature_request&.dismissed_at&.strftime("%b %-d, %Y")
      end

      memoize def show_copilot_individual_prompt?
        eligible_for_raf_copilot_prompt? &&
          no_copilot_access? &&
          !repo_owned_by_org?
      end

      def codespaces_path
        if @current_user&.feature_flag_enabled?(:codespaces_empty_repo_init, default: false)
          routes.new_with_nwo_codespaces_path(@repository&.owner, @repository, resume: 1, auto_init: 1)
        else
          routes.repository_codespaces_path(@repository&.owner, @repository)
        end
      end

      def copilot_org_admin_prompt
        {
          variant: "copilot-org-admin",
          icon: :copilot,
          title: "Set up GitHub Copilot",
          description: "Use GitHub's AI pair programmer to autocomplete suggestions as you code.",
          button_label: "Get started with GitHub Copilot",
          href: routes.copilot_business_signup_organization_payment_path(org: repo_organization),
          analytics: {
            category: "copilot_for_business_setup",
            action: "click_to_buy_copilot_for_business",
            label: "ref_cta:set_up_github_copilot;ref_loc:empty_repo;",
          },
        }
      end

      def copilot_org_member_prompt
        org = repo_organization
        action_path = routes.org_member_feature_requests_path(org: org&.display_login)
        feature = MemberFeatureRequest::Feature::CopilotForBusiness
        {
          variant: "copilot-org-member",
          icon: :copilot,
          title: "Take flight with GitHub Copilot",
          description: "Use GitHub's AI pair programmer to autocomplete suggestions as you code.",
          button_label: "Ask admin for access",
          href: action_path,
          requester: @current_user,
          organization: org,
          feature: feature,
          feature_request: {
            feature: feature.to_s,
            organization: org&.display_login,
            actionPath: action_path,
            requested: copilot_for_business_requested?,
            dismissed: copilot_for_business_dismissed?,
            dismissedAt: copilot_for_business_dismissed_at,
            featureName: feature.name,
          },
          analytics: {
            category: "member_feature_request",
            action: "action.#{MemberFeatureRequest::Feature::CopilotForBusiness}",
            label: "ref_cta:ask_admin_for_access to GitHub Copilot;ref_loc:empty repo;",
          },
        }
      end

      def copilot_individual_prompt
        href = user_part_of_org? ? routes.copilot_settings_path : routes.copilot_signup_path
        {
          variant: "copilot-individual",
          icon: :copilot,
          title: "Set up GitHub Copilot",
          description: "Use GitHub's AI pair programmer to autocomplete suggestions as you code.",
          button_label: "Get started with GitHub Copilot",
          href: href,
          analytics: {
            category: "copilot_trial_signup",
            action: user_part_of_org? ? "click_to_view_copilot_settings" : "click_to_sign_up_for_copilot_trial",
            label: "ref_cta:set_up_github_copilot;ref_loc:empty_repo;",
          },
        }
      end

      def codespaces_prompt
        {
          variant: "codespaces",
          icon: :codespaces,
          title: "Start coding with Codespaces",
          description: "Add a README file and start coding in a secure, configurable, and dedicated development environment.",
          button_label: "Create a codespace",
          href: codespaces_path,
          analytics: {
            category: "repository_onboarding",
            action: "click_to_create_a_codespace",
            label: "ref_cta:create_a_codespace;ref_loc:empty_repo;",
          },
        }
      end

      def org_admin_prompt
        {
          variant: "org-admin",
          icon: :people,
          title: "Give access to the people you work with",
          description: "Ensure the right people and teams have access to this repository.",
          button_label: "Add teams and collaborators",
          href: routes.repository_access_management_path(@repository.owner, @repository),
          analytics: {
            category: "repository_onboarding",
            action: "click_to_add_teams_and_collaborators",
            label: "ref_cta:give_access_to_the_people_you_work_with;ref_loc:empty_repo;",
          },
        }
      end

      def org_prompt
        {
          variant: "org",
          icon: :"person-add",
          title: "Give access to the people you work with",
          description: "Ensure the right people and teams have access to this repository.",
          button_label: "Manage access",
          href: routes.repository_access_management_path(@repository.owner, @repository),
          analytics: {
            category: "repository_onboarding",
            action: "click_to_manage_access",
            label: "ref_cta:give_access_to_the_people_you_work_with_you;ref_loc:empty_repo;",
          },
        }
      end

      def move_to_org_prompt
        account = @current_user
        href = if account&.organization?
          routes.org_move_work_new_path(account, repository: @repository)
        else
          routes.user_move_work_new_path(repository: @repository)
        end

        {
          variant: "move-to-org",
          icon: :people,
          title: "Move to an organization",
          description: "Collaborate across many projects, with security and administrative features.",
          button_label: "Move repository",
          href: href,
          analytics: {
            category: "repository_onboarding",
            action: "click_to_move_work",
            label: "ref_cta:move_to_an_organization;ref_loc:empty_repo;",
          },
        }
      end

      def user_default_prompt
        {
          variant: "user-default",
          icon: :"person-add",
          title: "Add collaborators to this repository",
          description: "Search for people using their GitHub username or email address.",
          button_label: "Invite collaborators",
          href: routes.repository_access_management_path(@repository.owner, @repository),
          analytics: {
            category: "repository_onboarding",
            action: "click_to_add_collaborators",
            label: "ref_cta:invite_collaborators;ref_loc:empty_repo;",
          },
        }
      end
    end
  end
end
