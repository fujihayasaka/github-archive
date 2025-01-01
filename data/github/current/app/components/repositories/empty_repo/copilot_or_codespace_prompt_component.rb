# typed: strict
# frozen_string_literal: true
module Repositories
  module EmptyRepo
    class CopilotOrCodespacePromptComponent < ApplicationComponent
      include MemberFeatureRequestsHelper

      include ApplicationComponent::Rescuable
      rescue_from StandardError, with: :nothing

      sig { returns T::Hash[Symbol, T.untyped] }
      attr_reader :system_arguments

      sig { returns T.nilable(Repository) }
      attr_reader :repository

      sig { returns T.nilable(User) }
      attr_reader :user

      sig do
        params(
          user_can_push: T::Boolean,
          user: T.nilable(User),
          copilot_user: T.nilable(Copilot::User),
          repository: T.nilable(Repository),
          system_arguments: T.untyped
        ).void
      end
      def initialize(user_can_push:, user: nil, copilot_user: nil, repository: nil, **system_arguments)
        @user_can_push = user_can_push
        @user = T.let(user, T.nilable(User))
        @copilot_user = T.let(copilot_user, T.nilable(Copilot::User))
        @repository = T.let(repository, T.nilable(Repository))
        @system_arguments = system_arguments
      end

      sig { returns T::Boolean }
      def render?
        return false unless @repository
        true
      end

      sig { returns T.nilable(Organization) }
      memoize def repo_organization
        @repository&.organization
      end

      sig { returns T::Boolean }
      memoize def repository_owned_by_organization?
        return false unless @repository
        @repository.in_organization?
      end

      sig { returns T::Boolean }
      memoize def eligible_for_raf_copilot_prompt?
        # we're avoiding any Enterprise cases for now
        !repo_organization&.business
      end

      sig { returns T::Boolean }
      memoize def user_is_org_admin?
        return false unless repository_owned_by_organization?
        return false unless org = repo_organization
        org.adminable_by?(@user)
      end

      sig { returns T.nilable(Copilot::User) }
      memoize def copilot_user
        return @copilot_user if @copilot_user
        return unless @user
        Copilot::User.new(@user)
      end

      sig { returns T::Boolean }
      memoize def free_copilot_access?
        return true if copilot_user&.has_free_access?
        return true if copilot_user&.can_signup_for_free?
        false
      end

      sig { returns T::Boolean }
      memoize def no_copilot_access?
        !copilot_user&.access_allowed?
      end

      sig { returns T::Boolean }
      memoize def user_part_of_org?
        return false unless @user
        @user.member_or_billing_manager_for_any_organization?
      end

      sig { returns String }
      memoize def codespaces_prompt_path
        return new_with_nwo_codespaces_path(@repository&.owner, @repository, resume: 1, auto_init: 1) if @user&.feature_enabled?(:codespaces_empty_repo_init)
        repository_codespaces_path(@repository)
      end

      sig { returns T::Boolean }
      memoize def eligible_raf_organization_copilot_prompt?
        return false unless eligible_for_upsell?(
          feature: MemberFeatureRequest::Feature::CopilotForBusiness,
          requester: @user,
          request_entity: @repository&.organization
        )
        org_admin_without_copilot = user_is_org_admin? && no_copilot_access?
        org_member_without_free_copilot = !user_is_org_admin? && !free_copilot_access?

        org_admin_without_copilot || org_member_without_free_copilot
      end

      sig { returns T::Boolean }
      memoize def show_copilot_organization_admin_prompt?
        return false unless eligible_for_raf_copilot_prompt?
        return false unless repository_owned_by_organization?
        return false unless eligible_raf_organization_copilot_prompt?
        return false unless user_is_org_admin?
        true
      end

      sig { returns T::Boolean }
      memoize def show_copilot_organization_member_prompt?
        return false unless eligible_for_raf_copilot_prompt?
        return false unless repository_owned_by_organization?
        return false unless eligible_raf_organization_copilot_prompt?
        return false unless !user_is_org_admin?
        true
      end

      sig { returns T::Boolean }
      memoize def show_copilot_individual_prompt?
        return false unless eligible_for_raf_copilot_prompt?
        return false unless no_copilot_access?
        return false if repository_owned_by_organization?
        true
      end

      sig { returns T::Boolean }
      memoize def show_codespace_prompt?
        @user_can_push
      end
    end
  end
end
