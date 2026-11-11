# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrant
  class AccessLevel
    class InvalidAttributeError < ArgumentError; end

    attr_reader :permissions, :repository_ids, :repository_selection

    def initialize(permissions:, repository_ids:, repository_selection:)
      @permissions = permissions
      @repository_ids = repository_ids
      @repository_selection = repository_selection.to_s

      validate_repository_selection!
    end

    def self.from_grantable(grantable)
      validate_grantable!(grantable)

      new(
        permissions: grantable.permissions,
        repository_ids: grantable.repository_ids,
        repository_selection: grantable.repository_selection
      )
    end

    def self.validate_grantable!(grantable)
      required_attributes =
        grantable.respond_to?(:permissions) &&
        grantable.respond_to?(:repository_ids) &&
        grantable.respond_to?(:repository_selection)

      raise InvalidAttributeError unless required_attributes
    end

    def self.from_hash(hash)
      raise InvalidAttributeError, "hash is invalid" unless valid_hash(hash)
      attrs = hash.slice(:permissions, :repository_selection)

      attrs[:repository_ids] =
        if hash[:repository_ids]
          hash[:repository_ids]
        elsif hash[:repositories]
          hash[:repositories].pluck :id
        else
          raise InvalidAttributeError, "hash is invalid"
        end

      new(**attrs)
    end

    def self.valid_hash(hash)
      return false unless hash
      %i(permissions repository_selection).all? { |key| hash.key?(key) }
    end

    def >(other)
      raise InvalidAttributeError unless other.is_a?(AccessLevel)

      higher_repository_selection_than?(other) ||
      more_or_different_repositories_than?(other) ||
      more_or_upgraded_permissions_than?(other)
    end
    alias greater_than? >

    private

    def validate_repository_selection!
      unless RepositorySelection::OPTION_ORDER[repository_selection]
        raise InvalidAttributeError, "repository_selection is invalid"
      end
    end

    def more_or_upgraded_permissions_than?(other)
      differ = PermissionsDiffer.new(
        previous_permissions: other.permissions,
        new_permissions: self.permissions
      )

      differ.added_permissions.any? || differ.upgraded_permissions.any?
    end

    def higher_repository_selection_than?(other)
      RepositorySelection::OPTION_ORDER[self.repository_selection] >
        RepositorySelection::OPTION_ORDER[other.repository_selection]
    end

    def more_or_different_repositories_than?(other)
      return false unless other.repository_ids.present?

      (self.repository_ids - other.repository_ids).any?
    end
  end
end
