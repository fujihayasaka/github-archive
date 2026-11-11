# typed: true
# frozen_string_literal: true

module SecurityCenter
  class ArtifactFiltersPopoverComponent < ApplicationComponent
    ANALYTICS_CATEGORY = "Nudge"
    ANALYTICS_NUDGE_ID = "artifact-filters"

    SURFACE_BY_NOTICE = T.let({
      dependabot_alerts_artifact_filters_popover: "dependabot-alerts",
      code_scanning_alerts_artifact_filters_popover: "code-scanning-alerts",
    }.freeze, T::Hash[Symbol, String])

    sig do
      params(
        user: T.nilable(User),
        organization: Organization,
        notice_name: Symbol,
      ).void
    end
    def initialize(user:, organization:, notice_name:)
      @user = user
      @organization = organization
      @notice_name = notice_name
    end

    sig { override.returns(T::Boolean) }
    def render?
      return false if GitHub.single_tenant_enterprise?
      return false if @user.blank?
      return false if @user.dismissed_notice?(@notice_name)

      has_artifact_data?
    end

    sig { returns(String) }
    def analytics_surface
      SURFACE_BY_NOTICE.fetch(@notice_name, @notice_name.to_s)
    end

    sig { returns(String) }
    def analytics_label
      "surface:#{analytics_surface};nudge:#{ANALYTICS_NUDGE_ID}"
    end

    private

    sig { returns(T::Boolean) }
    def has_artifact_data?
      ArtifactDeploymentRecord
        .where(owner_id: @organization.id, deleted_at: nil)
        .exists? ||
      ArtifactStorageRecord
        .joins(:artifact_metadata)
        .where(artifact_metadata: { owner_id: @organization.id })
        .where(deleted_at: nil)
        .exists?
    end
  end
end
