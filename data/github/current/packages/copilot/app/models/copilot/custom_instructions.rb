# typed: strict
# frozen_string_literal: true

module Copilot
  class CustomInstructions < ApplicationRecord::Copilot

    CustomInstructionJson = T.type_alias do
      {
        type: Symbol,
        prompt: String,
        owner: String,
        apply_to: T::nilable(T::Array[String]),
        name: T.nilable(String),
      }
    end

    after_commit :instrument_create, on: :create
    after_commit :instrument_update, on: :update

    # The custom instructions will take valuable space in the context window so we don't want them to get too big so
    # we'll set a limit. See: https://github.com/github/copilot-core-productivity/issues/1872
    CHAR_LIMIT = 4_000

    REPO_CUSTOM_INSTRUCTIONS_PATH = ".github/copilot-instructions.md"
    REPO_CUSTOM_INSTRUCTIONS_FILE_LIMIT = T.let(5.kilobytes, Integer)

    REPO_INSTRUCTIONS_MD_DIR = ".github/instructions"

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

    sig { params(owner_id: Integer, owner_login: String).returns(T.nilable(CustomInstructionJson)) }
    def self.for_organization_by_id(owner_id, owner_login)
      organization = ::Organization.find_by(id: owner_id)
      return unless organization.present?

      ref = Copilot::CustomInstructions.where(owner_id: organization.id, owner_type: "Organization").last
      return unless ref.present? && ref.prompt.present?
      {
        type: :Organization,
        prompt: ref.prompt,
        owner: owner_login,
        apply_to: nil,
        name: "org-custom-instructions",
      }.compact
    end

    # NOTE: repo-level instructions are not actually persisted in the database. They are stored as
    #       a file in the repo, under `.github/copilot-instructions.md`.
    sig { params(repo: ::Repository, oid: T.nilable(String)).returns(T.nilable(CustomInstructionJson)) }
    def self.for_repository(repo, oid = nil)
      return unless GitRPC::Util.valid_full_oid?(oid || repo.default_oid)

      begin
        blob = repo.blob(
          oid || repo.default_oid,
          REPO_CUSTOM_INSTRUCTIONS_PATH,
          { truncate: REPO_CUSTOM_INSTRUCTIONS_FILE_LIMIT },
        )
      rescue GitRPC::InvalidObject => ex
        # Sometimes this error is thrown when the oid is for a tag.
        # It is unclear how to reproduce the error, and falling
        # back to nil custom instructions is better than crashing.
        GitHub.logger.error("failed to load custom instructions for repository", {
          "exception.message": ex.full_message,
          "exception.type": ex.class.name
        })
        GitHub.dogstats.increment("copilot.custom_instructions.failed_to_load_oid")
        return
      end

      prompt = blob&.data
      return unless prompt.present?

      {
        type: :Repository,
        prompt: prompt,
        owner: repo.name_with_display_owner,
        apply_to: nil,
        name: blob.path,
      }.compact
    end

    # NOTE: repo-level instructions.md are not actually persisted in the database. They are stored in *.instruction.md files in a directory, under `.github/instructions`.
    sig { params(repo: ::Repository, pr_ref: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[CustomInstructionJson])) } # rubocop:disable Sorbet/ForbidTUntyped
    def self.repo_instructions_md(repo, pr_ref)
      oid = repo.default_oid
      return unless repo.feature_flag_enabled?(:ccr_repo_instructions_md, default: false)
      return unless GitRPC::Util.valid_full_oid?(oid)

      entries = []
      begin
        _, entries, _ = repo.tree_entries(oid, REPO_INSTRUCTIONS_MD_DIR, recursive: true)

      rescue GitRPC::InvalidObject => err
        # Sometimes this error is thrown when the oid is for a tag.
        # It is unclear how to reproduce the error, and falling
        # back to nil instructions.md is better than crashing.
        GitHub.logger.error("failed to load .instructions.md for repository", {
          "exception.message": err.full_message,
          "exception.type": err.class.name
        })
        GitHub.dogstats.increment("copilot.instructions-md.failed_to_load_oid")
        return
      # return with no logging for other errors like GitRPC::NoSuchPath, GitRPC::ObjectMissing, etc.
      rescue StandardError
        # Don't throw if we're unable to retrieve entry items.
        return
      end
      return if entries.size == 0

      result = entries.filter_map do |entry|
        next if entry.directory? || entry.data.blank?
        next unless entry.path.match(%r{\.github/instructions/.*\.instructions\.md\z})

        content = FrontMatter.new(entry.data)
        front_matter = content.parsed_yaml
        prompt = content.body

        next unless prompt.present?

        apply_to = extract_apply_to(repo:, front_matter:)
        next if apply_to.blank?
        files = pr_ref.dig(:data, :files).map { |f| f[:fileName] }
        next unless instruction_applies_to_diff?(files:, apply_to:)

        {
          type: :Repository,
          prompt:,
          owner: repo.name_with_display_owner,
          apply_to:,
          name: conditionally_add_name(repo:, repo_object: entry),
        }.compact
      end
      result.empty? ? nil : result
    end

    sig { returns(CustomInstructionJson) }
    def as_json
      {
        type: owner.type.to_sym,
        prompt: prompt,
        owner: owner.name_with_display_owner,
        apply_to: nil,
        name: nil,
      }.compact
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

    sig { params(repo: ::Repository, front_matter: T::nilable(T::Hash[String, Object])).returns(T::nilable(T::Array[String])) }
    private_class_method def self.extract_apply_to(repo:, front_matter:)
      return unless repo.feature_flag_enabled?(:ccr_extras_in_custom_instructions_json, default: false)
      return unless front_matter.present? && front_matter.key?("applyTo")

      apply_to = front_matter["applyTo"]
      # If the frontmatter is already formatted as an array let's accept it
      # Instructions.md are documented as a string that contains
      # comma-separated path regexes
      return apply_to if apply_to.is_a?(Array)
      return unless apply_to && apply_to.is_a?(String)
      apply_to.split(",").map(&:strip)
    end

    sig { params(repo: ::Repository, repo_object: T::any(TreeEntry, T::Hash[String, String])).returns(T.nilable(String)) }
    private_class_method def self.conditionally_add_name(repo:, repo_object:)
      return unless repo.feature_flag_enabled?(:ccr_extras_in_custom_instructions_json, default: false)
      repo_object["path"]
    end

    sig { params(files: T::nilable(T::Array[String]), apply_to: T::nilable(T::Array[String])).returns(T::Boolean) }
    private_class_method def self.instruction_applies_to_diff?(files:, apply_to:)
      return true if files.blank? || apply_to.blank?

      files.any? do |filename|
        apply_to.any? do |pattern|
          File.fnmatch(pattern, filename)
        end
      end
    end
  end
end
