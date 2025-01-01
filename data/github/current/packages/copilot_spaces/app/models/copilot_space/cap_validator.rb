# typed: true
# frozen_string_literal: true

class CopilotSpace
  class CapValidator < T::Struct
    const :cap_filter, ConditionalAccess::Filter
    const :copilot_space, CopilotSpace
    const :current_user, User

    sig { params(action: Symbol).void }
    def validate_space(action)
      validate_owner if action == :create
      validate_resources_updated_via_nested_attributes
    end

    sig { void }
    def validate_owner
      return unless copilot_space.owner.present?
      return unless current_user.present?

      if copilot_space.owner.user?
        if copilot_space.owner.id != current_user.id
          copilot_space.cap_validator_errors.add(:base, "Unable to create a space for this user.")
        end
      elsif copilot_space.owner.organization?
        authorized_orgs = CopilotSpaces::AuthorizationHelper.authorized_orgs_with_copilot_access(
          current_user,
          cap_filter
        )

        unless authorized_orgs.find { |org| org.id == copilot_space.owner.id }.present?
          copilot_space.cap_validator_errors.add(:base, "Unable to create a space for this organization.")
        end
      else
        copilot_space.cap_validator_errors.add(:base, "The owner is invalid.")
      end
    end

    # This method is specifically for validating resources updated via nested attributes,
    # either during creation or updates. This method should only be called after the attributes
    # have been assigned to the space and before it has been saved.
    # Upon assignment rails will either build new records or look up changed records by their ID and assign them to the
    # collection proxy, see https://github.com/rails/rails/blob/b0c813bc7b61c71dd21ee3a6c6210f6d14030f71/activerecord/lib/active_record/nested_attributes.rb#L517
    # This is a reliable way for us to only validate the subset of resources that are being changed.
    sig { void }
    def validate_resources_updated_via_nested_attributes
      records = T.let(copilot_space.resources.proxy_association.nested_attributes_target || [], T::Array[CopilotSpaceResource]).compact

      repo_ids = records.map { |resource| resource.repository_id }.uniq.compact
      repos = Repositories::Public.load_repositories(repo_ids).index_by(&:id)
      # CAP validation only applies to repository-based resources

      records.each do |resource|
        validate_resource_repository_access(resource, repos[resource.repository_id])
      end
    end

    sig { params(resource: CopilotSpaceResource, repository: T.nilable(Repository)).void }
    def validate_resource_repository_access(resource, repository)
      return unless resource.repository_based_resource?
      return if resource.repository_id.blank?

      errors = ActiveModel::Errors.new(resource)
      resource.cap_validator_errors = errors

      if repository.nil?
        errors.add(:repository, "not found")
        return
      end

      if !repository.public? &&
        T.must(resource.copilot_space).owner.is_a?(Organization) &&
        repository.owner != T.must(resource.copilot_space).owner
        errors.add(:repository, "not found")
        return
      end

      is_readable_by_user = repository.readable_by?(resource.current_user)
      is_cap_filter_authorized = cap_filter.unauthorized([repository]).empty?
      is_authorized_repo = is_readable_by_user && is_cap_filter_authorized

      errors.add(:repository, "not found") unless is_authorized_repo
    end
  end
end
