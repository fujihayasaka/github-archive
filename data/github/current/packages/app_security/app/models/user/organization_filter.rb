# typed: true
# frozen_string_literal: true

class User

  # Public: Filter the set of orgs that the user is a member of.
  class OrganizationFilter
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def scope
      return @user_organizations if defined?(@user_organizations)
      @user_organizations = Organization.where(id: scoped_ids).order(:id)
    end

    def scoped_ids
      is_memoized_organizations_ids = defined?(@user_organizations_ids)
      GitHub.dogstats.distribution_time("user.organization-filter.scoped-ids.duration", tags: ["is_memoized:#{!is_memoized_organizations_ids.nil?}", "governed_by_oauth_application_policy:#{user.governed_by_oauth_application_policy?}"]) do
        return @user_organizations_ids if is_memoized_organizations_ids
        @user_organizations_ids = if user.governed_by_oauth_application_policy?
          org_ids = Organization.oauth_app_policy_met_by(user.oauth_application).where(id: unscoped_ids).pluck(:id)
          org_ids |= user.public_organizations.pluck(:id)
        else
          unscoped_ids
        end
      end
    end

    def unscoped_ids
      GitHub.instrument "ability.user.organization-filter" do
        return [] if user.new_record?
        return [] if user.ability_delegate.nil?

        subject_ids = Ability.organization_memberships_for_user(user_id: user.id)
        Organization.active.where(id: subject_ids).pluck(:id).sort
      end
    end
  end
end
