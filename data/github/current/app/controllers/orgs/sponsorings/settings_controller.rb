# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::SettingsController < Orgs::Sponsorings::BaseController
  extend T::Sig

  before_action :sponsors_required
  before_action :login_required
  before_action :org_admins_only

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  sig { void }
  def show
    render "orgs/sponsorings/settings/show", locals: {
      owned_organizations: owned_organizations,
      linked_organization_id: linked_organization_id,
    }
  end

  sig { void }
  def update
    linked_org = current_user.owned_organizations.find_by_id(params[:linked_organization_id])
    if linked_org.blank?
      flash[:error] = "No linked organization was selected!"
      redirect_to org_sponsoring_settings_path
      return
    end

    OrganizationProfile.transaction do
      # Sorbet is confused about us using `update` on an AR::Relation. It thinks there needs to be an additional
      # argument for some reason, even though ActiveRecord sets the first argument to `:all` by default. To avoid
      # an error, we just do the same here.
      # See https://api.rubyonrails.org/v5.1/classes/ActiveRecord/Relation.html#method-i-update
      linked_organization_profiles.update(:all, sponsoring_linked_organization_id: nil)

      linked_org_not_this_org = this_organization != linked_org
      profile = linked_org.organization_profile
      if linked_org_not_this_org || profile.present?
        profile ||= linked_org.build_organization_profile
        profile.sponsoring_linked_organization = if linked_org_not_this_org
          this_organization
        else
          nil
        end

        unless profile.save
          flash[:error] = "Could not link organization: #{profile.errors.full_messages.to_sentence}"
        end
      end
    end

    redirect_to org_sponsoring_settings_path
  end

  private

  sig { returns(ActiveRecord::Relation) }
  def linked_organization_profiles
    OrganizationProfile.for_sponsoring_linked_org(this_organization.id)
  end

  sig { returns(T.nilable(Integer)) }
  def linked_organization_id
    linked_organization_profiles.pluck(:organization_id).first
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def owned_organizations
    # ensure this_organization is always first
    current_user.owned_organizations.order(Arel.sql("FIELD(users.id, #{this_organization.id}) desc"))
  end
end
