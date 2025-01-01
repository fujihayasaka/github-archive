# typed: true
# frozen_string_literal: true

module VerifiableDomainsControllerMethods
  extend ActiveSupport::Concern
  include GitHub::Memoizer
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    helper_method :this_business
  end

  private

  def owner_profile_domains
    return [] unless owner.is_a?(Organization)

    [owner.profile_blog, owner.profile_email].reject(&:blank?).map do |domain|
      VerifiableDomain.normalize_domain(domain.to_s)
    end.uniq
  end

  memoize def owner
    if organization_login_param.present?
      Organization.find_by!(login: organization_login_param)
    elsif business_slug_param.present?
      Business.find_by!(slug: business_slug_param)
    end
  end

  def find_owner!
    raise ActiveRecord::RecordNotFound if owner.nil?

    owner
  end

  # Before action that checks if owner is adminable by current user.
  def owner_admin_required
    return if owner.adminable_by?(current_user)

    render_404
  end

  # Before action that will 404 if verified domains aren't enabled.
  def check_verified_domains_enabled
    render_404 unless GitHub.verified_domains_enabled?
  end

  def business_slug_param
    params[:slug].presence&.to_s
  end

  def organization_login_param
    # Organization routes use a mixture of :org and :organization_id params:
    #  - index:    /organizations/:organization_id/settings/domains
    #  - the rest: /orgs/:org/domains/<domain-id>/action
    (params[:org].presence || params[:organization_id].presence)&.to_s
  end

  # Safe because :find_owner! will raise if owner is nil.
  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end

  def this_business
    owner.is_a?(Business) ? owner : nil
  end

  def ensure_if_organization_required
    render_404 if owner.is_a?(Organization) && owner.deleted?
  end
end
