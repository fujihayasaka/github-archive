# typed: strict
# frozen_string_literal: true

module Copilot
  class CustomInstructions < ApplicationRecord::Copilot

    CustomInstructionJson = T.type_alias do
      {
        type: Symbol,
        prompt: String,
        owner: String
      }
    end

    after_commit :instrument_create, on: :create
    after_commit :instrument_update, on: :update

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

    sig { params(user: ::User).returns(T.nilable(Copilot::CustomInstructions)) }
    def self.for_user(user)
      Copilot::CustomInstructions.where(owner: user).last
    end

    sig { params(organization: ::Organization).returns(T.nilable(Copilot::CustomInstructions)) }
    def self.for_organization(organization)
      Copilot::CustomInstructions.where(owner_id: organization.id, owner_type: "Organization").last
    end

    # NOTE: repo-level instructions are not actually persisted in the database. They are stored as
    #       a file in the repo, under `.github/copilot-instructions.md`.
    sig { params(repo: ::Repository, oid: T.nilable(String)).returns(T.nilable(CustomInstructionJson)) }
    def self.for_repository(repo, oid = nil)
      return nil unless GitRPC::Util.valid_full_oid?(oid || repo.default_oid)

      prompt = repo.blob(
        oid || repo.default_oid,
        REPO_CUSTOM_INSTRUCTIONS_PATH,
        { truncate: REPO_CUSTOM_INSTRUCTIONS_FILE_LIMIT },
      )&.data

      return nil unless prompt

      {
        type: :Repository,
        prompt: prompt,
        owner: repo.name_with_display_owner
      }
    end

    sig { returns(CustomInstructionJson) }
    def as_json
      {
        type: owner.type.to_sym,
        prompt: prompt,
        owner: owner.name_with_display_owner
      }
    end

    private

    sig { void }
    def instrument_create
      Copilot::Instrumenter.instrument_custom_instructions_created(self)
    end

    sig { void }
    def instrument_update
      Copilot::Instrumenter.instrument_custom_instructions_updated(self)
    end
  end
end
