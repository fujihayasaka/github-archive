# typed: strict
# frozen_string_literal: true

module Copilot
  class CustomInstructions < ApplicationRecord::Copilot
    extend T::Sig

    # The custom instructions will take valuable space in the context window so we don't want them to get too big so
    # we'll set a limit. See: https://github.com/github/copilot-core-productivity/issues/1872
    CHAR_LIMIT = 600

    self.table_name = "copilot_custom_instructions"
    self.strict_loading_by_default = true

    # Right now a custom instructions only belong to an org but we may expand to users later and this will make that
    # transition simpler.
    #
    # See: https://github.com/github/github/pull/327723#discussion_r1629877137
    belongs_to :owner, polymorphic: true, optional: true, strict_loading: false

    validates :prompt, length: { maximum: CHAR_LIMIT }

    sig { params(organization: ::Organization).returns(T.nilable(Copilot::CustomInstructions)) }
    def self.for_organization(organization)
      Copilot::CustomInstructions.where(owner: organization).last
    end

    sig { params(user: ::User).returns(T.nilable(String)) }
    def self.visible_to_user(user)
      return nil unless user.feature_enabled?(:copilot_chat_custom_instructions)

      orgs = user.organizations
      where(owner_id: orgs.pluck(:id), owner_type: "Organization").includes(:owner).find do |custom_instructions|
        custom_instructions.prompt.present? && Copilot::Organization.new(custom_instructions.owner).can_use_copilot_enterprise_features?
      end&.prompt
    end
  end
end
