# typed: strict
# frozen_string_literal: true

module Copilot
  class CustomInstructions < ApplicationRecord::Copilot

    # The custom instructions will take valuable space in the context window so we don't want them to get too big so
    # we'll set a limit. See: https://github.com/github/copilot-core-productivity/issues/1872
    CHAR_LIMIT = 600

    REPO_CUSTOM_INSTRUCTIONS_PATH = ".github/copilot-instructions.md"
    REPO_CUSTOM_INSTRUCTIONS_FILE_LIMIT = T.let(5.kilobytes, Integer)

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

    # NOTE: repo-level instructions are not actually persisted in the database. They are stored as
    #       a file in the repo, under `.github/copilot-instructions.md`.
    sig { params(repo: ::Repository, oid: T.nilable(String)).returns(T.nilable(String)) }
    def self.for_repository(repo, oid = nil)
      return unless GitRPC::Util.valid_full_oid?(oid || repo.default_oid)

      repo.blob(
        oid || repo.default_oid,
        REPO_CUSTOM_INSTRUCTIONS_PATH,
        { truncate: REPO_CUSTOM_INSTRUCTIONS_FILE_LIMIT },
      )&.data
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
