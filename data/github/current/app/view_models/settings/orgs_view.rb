# typed: true
# frozen_string_literal: true

module Settings
  class OrgsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::Memoizer

    # Public: Return a Membership for each associated organization, collapsing
    # multiple assocations for one organization into a single Membership and
    # preferring the membership that includes the most information.
    #
    # Returns an Array of memberships.
    def memberships
      memberships = []

      organizations.each do |org|
        memberships << Membership.new(
          current_user,
          org,
          repository_count: repo_count_by_organization_id[org.id] || 0,
          role: role_for(org),
        )
      end

      # Put the orgs eligible for upgrade up front, but maintain the original order
      eligible_for_upgrade = []
      memberships.each do |membership|
        if membership.show_upgrade_button?
          eligible_for_upgrade << memberships.delete(membership)
        end
      end
      memberships.prepend(*eligible_for_upgrade)
    end

    memoize def eligible_organization_count
      memberships.count(&:show_upgrade_button?)
    end

    # Provides a membership description and delete confirmation method for a
    # user and organization assocation as well as the organization, number of
    # direct repo memberships in the organization, and organization name.
    class Membership
      include UrlHelpers
      include EnterpriseManagedUsersHelper
      include GitHub::Memoizer
      include ActionView::Helpers::TextHelper

      SETTINGS_AUTHORIZED_ROLES = [:owner, :moderator, :moderator_and_outside_collaborator, :billing_manager]
      COMPARE_PLANS_ROLES = [:owner, :billing_manager]

      def initialize(user, organization, repository_count: 0, role:)
        @user = user
        @repository_count = repository_count
        @organization = organization
        @name = organization.display_login
        @role = role
      end

      attr_reader :organization, :repository_count, :name, :user, :role

      def description
        case role
        when :owner
          "Owner"
        when :moderator
          "Moderator"
        when :member
          "Member"
        when :outside_collaborator
          "#{outside_collaborators_verbiage(@organization).singularize.capitalize} on #{pluralize(repository_count, 'repository')}"
        when :member_and_outside_collaborator
          "Member and collaborator on #{pluralize(repository_count, 'repository')}"
        when :moderator_and_outside_collaborator
          "Moderator and collaborator on #{pluralize(repository_count, 'repository')}"
        when :billing_manager
          "Billing manager"
        end
      end

      def delete_confirmation_message
        message = ["Are you positive you want to leave #{organization.display_login}?"]

        message << \
          case role
          when :owner, :member, :moderator, :moderator_and_outside_collaborator, :member_and_outside_collaborator
            "You will lose access to all repositories and teams."
          when :outside_collaborator
            "You will lose access to all repositories."
          when :billing_manager
            "You will lose access to billing settings."
          else
            ""
          end

        message.join(" ")
      end

      def request_status_message(feature_request)
        return request_status_message_with_copilot if has_copilot_for_business?
        return "Request submitted to admin for access to Copilot." if feature_request.requested_for_enterprise?
        return "Request for #{::Copilot.business_product_name} submitted." if feature_request.requested_for_organization?

        ""
      end

      def request_status_message_with_copilot
        if has_copilot_seat_for_user?
          "Admins have enabled Copilot for this organization and have given you access."
        else
          "Admins have enabled Copilot for this organization, but you don't have access."
        end
      end

      def org_settings_path
        case role
        when :owner
          settings_org_profile_path(organization)
        when :moderator, :moderator_and_outside_collaborator
          organization_settings_blocked_users_path(organization)
        when :billing_manager
          settings_org_billing_path(organization)
        end
      end

      def show_settings_button?
        SETTINGS_AUTHORIZED_ROLES.include?(role)
      end

      def show_compare_plans?
        return false unless GitHub.billing_enabled?
        return false if organization.archived?
        return false unless COMPARE_PLANS_ROLES.include?(role)
        return false if organization.plan.business_plus?
        return false if organization.business

        true
      end

      def show_request_for_copilot_button?
        return false if has_copilot_seat_for_user?
        copilot_user = ::Copilot::User.new(user)
        return false if copilot_user.has_free_access? || copilot_user.can_signup_for_free?

        true
      end

      memoize def copilot_organization
        ::Copilot::Organization.new(organization)
      end

      memoize def has_copilot_for_business?
        copilot_organization&.has_copilot_for_business?
      end

      memoize def has_copilot_seat_for_user?
        copilot_organization&.has_seat_for?(user)
      end

      memoize def show_upgrade_button?
        return false unless role == :owner

        organization.eligible_for_upgrade_to_enterprise?
      end
    end

    def two_factor_requirement_enabled?(org)
      two_factor_configuration_entries.include?(["User", org.id]) || two_factor_configuration_entries.include?(["Business", org.business&.id])
    end

    def prevent_removal_of_scim_managed_user?(org)
      ability = organization_abilities.select { |a| a.subject_id == org.id }
      return false unless ability.any?
      derived_organization_membership_entries.any? { |e| e.organization_id == org.id && e.ability_id == ability.first.id }
    end

    private

    def organizations
      return @organizations if defined?(@organizations)
      org_ids = (current_user.member_or_billing_manager_organization_ids + repo_count_by_organization_id.keys).uniq
      @organizations = ::Organization.where(id: org_ids).includes(:business).order(login: :asc).reject { |org| org.deleted? }
    end

    def repo_count_by_organization_id
      @repo_count_by_organization_id ||= ::Repository.active.with_organization.where({
        id: current_user.associated_repository_ids(including: [:direct]),
      }).group(:organization_id).count
    end

    def role_for(organization)
      role_data = role_data_by_organization_id[organization.id]

      if role_data[:owner]
        :owner
      elsif role_data[:moderator]
        role_data[:outside_collaborator] ? :moderator_and_outside_collaborator : :moderator
      elsif role_data[:member]
        role_data[:outside_collaborator] ? :member_and_outside_collaborator : :member
      elsif role_data[:billing_manager]
        :billing_manager
      else
        :outside_collaborator
      end
    end

    memoize def organization_abilities
      Ability.direct.where(subject_type: "Organization", actor_type: "User", actor_id: current_user.id).all
    end

    memoize def organization_moderation_abilities
      Ability.direct.where(subject_type: "Organization::Moderation", actor_type: "User", actor_id: current_user.id).all
    end

    memoize def derived_organization_membership_entries
      OrganizationMembershipEntry.where(user_id: current_user.id, adder_type: :external_team).all
    end

    memoize def two_factor_configuration_entries
      ::Configuration::Entry.where(target_id: (organizations + current_user.businesses).pluck(:id), name: "two_factor.required").pluck(:target_type, :target_id)
    end

    def role_data_by_organization_id
      return @role_data_by_organization_id if defined?(@role_data_by_organization_id)

      member_orgs = organization_abilities.pluck(:subject_id)
      moderator_orgs = GitHub.organization_moderators_enabled? ? organization_moderation_abilities.select { |a| a.can?(:write) }.pluck(:subject_id) : []
      @role_data_by_organization_id = organizations.each_with_object({}) do |org, results|
        results[org.id] = role_data_for(org, is_member: member_orgs.include?(org.id), is_moderator: moderator_orgs.include?(org.id))
      end
    end

    def role_data_for(organization, is_member:, is_moderator:)
      repo_count = repo_count_by_organization_id[organization.id] || 0

      {
        owner: current_user.owned_organization_ids.include?(organization.id),
        moderator: is_moderator,
        billing_manager: current_user.billing_manager_organization_ids.include?(organization.id),
        member: is_member,
        outside_collaborator: repo_count > 0,
      }
    end
  end
end
