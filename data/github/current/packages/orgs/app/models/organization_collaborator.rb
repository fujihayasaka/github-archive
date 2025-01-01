# typed: true
# frozen_string_literal: true

class OrganizationCollaborator < ApplicationRecord::Domain::UsersCollab
  extend T::Sig

  scope :with_org_and_user, ->(org, user) { where(user_id: user.id, organization_id: org.id) }

  sig { params(org: Organization).void }
  def self.backfill_for_org(org)
    existing_ocs = OrganizationCollaborator.where(organization_id: org.id).pluck(:user_id, :private, :public, :private_only_forks, :public_only_forks, :business_id, :id)
    existing_oc_ids = existing_ocs.map(&:first)
    private_ids = org.outside_collaborator_ids(on_repositories_with_visibility: [:private], include_forks: false, skip_cache: true).to_a
    private_fork_ids = org.outside_collaborator_ids(on_repositories_with_visibility: [:private], include_forks: true, skip_cache: true).to_a - private_ids
    public_ids = org.outside_collaborator_ids(on_repositories_with_visibility: [:public], include_forks: false, skip_cache: true).to_a
    public_fork_ids = org.outside_collaborator_ids(on_repositories_with_visibility: [:public], include_forks: true, skip_cache: true).to_a - public_ids
    user_ids = private_ids | public_ids | private_fork_ids | public_fork_ids
    org_id = org.id
    business_id = org.business&.id
    new_oc_ids = user_ids - existing_oc_ids
    remove_oc_ids = existing_oc_ids - user_ids
    update_oc_ids = existing_oc_ids - remove_oc_ids - new_oc_ids
    if new_oc_ids.any?
      with_write do
        OrganizationCollaborator.insert_all(
          new_oc_ids.map do |id|
            {
              user_id: id,
              organization_id: org_id,
              business_id: business_id,
              public: public_ids.include?(id),
              public_only_forks: public_fork_ids.include?(id),
              private: private_ids.include?(id),
              private_only_forks: private_fork_ids.include?(id),
            }
          end
        )
      end
    end
    if update_oc_ids.any?
      existing_ocs.each do |oc|
        id = oc.first
        next if oc[5] == business_id && oc[1] == private_ids.include?(id) && oc[2] == public_ids.include?(id) && oc[3] == private_fork_ids.include?(id) && oc[4] == public_fork_ids.include?(id)
        with_write do
          OrganizationCollaborator.update(
            oc.last,
            business_id: business_id,
            public: public_ids.include?(id),
            public_only_forks: public_fork_ids.include?(id),
            private: private_ids.include?(id),
            private_only_forks: private_fork_ids.include?(id),
          )
        end
      end
    end
    with_write { OrganizationCollaborator.where(organization_id: org.id, user_id: remove_oc_ids).destroy_all } if remove_oc_ids.any?
  end

  sig { params(org: Organization, user: User).returns(T.nilable(OrganizationCollaborator)) }
  def self.update_for_org_and_user(org, user)
    existing_record = OrganizationCollaborator.with_org_and_user(org, user).first
    private_collab = org.outside_collaborator_ids(on_repositories_with_visibility: [:private], include_forks: false, actor_ids: [user.id], skip_cache: true).any?
    private_fork_collab = !private_collab && org.outside_collaborator_ids(on_repositories_with_visibility: [:private], include_forks: true, actor_ids: [user.id], skip_cache: true).any?
    public_collab = org.outside_collaborator_ids(on_repositories_with_visibility: [:public], include_forks: false, actor_ids: [user.id], skip_cache: true).any?
    public_fork_collab = !public_collab && org.outside_collaborator_ids(on_repositories_with_visibility: [:public], include_forks: true, actor_ids: [user.id], skip_cache: true).any?
    is_collab = private_collab || public_collab || private_fork_collab || public_fork_collab
    if existing_record.present?
      if !is_collab
        with_write { existing_record.destroy }
        return nil
      else
        with_write do
          existing_record.update(
            business_id: org.business&.id,
            public: public_collab,
            public_only_forks: public_fork_collab,
            private: private_collab,
            private_only_forks: private_fork_collab
          )
        end
        return existing_record
      end
    elsif is_collab
      return with_write do
        OrganizationCollaborator.create(
          user_id: user.id,
          organization_id: org.id,
          business_id: org.business&.id,
          public: public_collab,
          public_only_forks: public_fork_collab,
          private: private_collab,
          private_only_forks: private_fork_collab
        )
      end
    end
    nil
  end
end
