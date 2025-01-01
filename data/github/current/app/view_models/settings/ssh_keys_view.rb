# typed: false
# frozen_string_literal: true

module Settings
  class SshKeysView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :ssh_keys, :git_signing_ssh_public_keys

    def ssh_disabled?
      GitHub.enterprise? && !GitHub.ssh_enabled? && GitHub.ssh_policy?
    end

    def show_ssh_cas?
      !ssh_disabled? && (affiliated_cas_via_org_membership.any? || affiliated_cas_via_repo_membership.any?)
    end

    # SSH CAs that might issue certificates for this user because they are a
    # member of the org or business.
    #
    # Returns an Hash mapping CA owners to Arrays of SshCertificateAuthority
    # instances.
    def affiliated_cas_via_org_membership
      return @affiliated_cas_via_org_membership if defined?(@affiliated_cas_via_org_membership)

      org_ids = current_user.organization_ids
      business_ids = current_user.business_ids

      if current_user.guest_collaborator?
        business_ids = [current_user.enterprise_managed_business.id]
      end

      if org_ids.empty? && business_ids.empty?
        return @affiliated_cas_via_org_membership = {}
      end

      cas = ::SshCertificateAuthority.where(
        owner_type: ::Organization.base_class.name,
        owner_id: org_ids,
      ).or(::SshCertificateAuthority.where(
        owner_type: ::Business.name,
        owner_id: business_ids,
      )).all

      ::SshCertificateAuthority.load_owners(cas)

      @affiliated_cas_via_org_membership = cas.group_by(&:owner).values
    end

    # SSH CAs that might issue a certificate for this user because the user is
    # an outside collaborator on a repository that is owned by the CA owner.
    #
    # Returns a Hash mapping Arrays of SshCertificateAuthrotiy instances =
    # (grouped by owner) to Arrays of Repository instances.
    def affiliated_cas_via_repo_membership
      if current_user.is_enterprise_managed?
        return {}
      end

      return @affiliated_cas_via_repo_membership if defined?(@affiliated_cas_via_repo_membership)

      org_repos = current_user.member_repositories.where.not(
        organization_id: [nil, current_user.organization_ids],
      ).all
      return @affiliated_cas_via_repo_membership = {} if org_repos.empty?

      org_ids = org_repos.map(&:organization_id).uniq

      boms = ::Business::OrganizationMembership.where(
        organization_id: org_ids,
      ).where.not(
        business_id: current_user.business_ids,
      ).all

      business_ids = boms.map(&:business_id).uniq

      cas = ::SshCertificateAuthority.where(
        owner_type: ::Organization.base_class.name,
        owner_id: org_ids,
      ).or(::SshCertificateAuthority.where(
        owner_type: ::Business.name,
        owner_id: business_ids,
      )).all
      return @affiliated_cas_via_repo_membership = {} if cas.empty?

      ::SshCertificateAuthority.load_owners(cas)

      # The records have been found. Now we need to put them together. For each
      # org/enterprise that has CAs, we're wanting to map a list of CAs to a
      # list of repositories that they can be used to access.

      repos_by_org_id = org_repos.each_with_object(Hash.new) do |repo, hash|
        hash[repo.organization_id] ||= []
        hash[repo.organization_id] << repo
      end

      org_ids_by_business_id = boms.each_with_object(Hash.new) do |bom, hash|
        hash[bom.business_id] ||= []
        hash[bom.business_id] << bom.organization_id
      end

      repos_by_ca_owner = cas.each_with_object(Hash.new) do |ca, hash|
        hash[ca.owner] = if ca.owner_type == ::Business.name
          org_ids_by_business_id[ca.owner_id].flat_map do |org_id|
            repos_by_org_id.fetch(org_id, [])
          end
        else
          repos_by_org_id.fetch(ca.owner_id, [])
        end
      end

      @affiliated_cas_via_repo_membership = cas.group_by(&:owner).values.each_with_object(Hash.new) do |cas, hash|
        hash[cas] = repos_by_ca_owner[cas.first.owner]
      end
    end

    def ca_owner_name(ca)
      if ca.owner_type == "Business"
        ca.owner.name
      else
        "@#{ca.owner.display_login}"
      end
    end

    def ca_owner_type(ca)
      if ca.owner_type == "Business"
        "enterprise"
      else
        "organization"
      end
    end

    def ca_owner_name_and_type(ca)
      if ca.owner_type == "Business"
        "#{ca.owner.slug} enterprise"
      else
        "@#{ca.owner.display_login} organization"
      end
    end
  end
end
