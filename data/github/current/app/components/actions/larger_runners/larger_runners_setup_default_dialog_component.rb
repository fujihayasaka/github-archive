# typed: strict
# frozen_string_literal: true

module Actions
  class LargerRunners::LargerRunnersSetupDefaultDialogComponent < ApplicationComponent
    extend T::Sig
    include Actions::LargerRunners::DefaultRunnersHelper

    sig { params(entity: T.any(Organization, Business)).void }
    def initialize(entity:)
      @entity = entity
    end

    sig { returns(String) }
    def setup_default_runners_path
      return settings_actions_setup_default_runners_enterprise_path(@entity) if @entity.is_a?(Business)

      settings_org_actions_setup_default_runners_path(@entity)
    end

    sig { returns(String) }
    def dismissal_path
      return enterprise_notice_path(@entity, notice: DEFAULT_RUNNERS_BANNER_NOTICE_NAME) if @entity.is_a?(Business)

      dismiss_org_notice_path(@entity, input: { organizationId: @entity.id, notice: DEFAULT_RUNNERS_BANNER_NOTICE_NAME })
    end
  end
end
