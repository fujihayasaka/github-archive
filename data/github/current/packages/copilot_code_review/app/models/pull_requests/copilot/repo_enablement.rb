# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class RepoEnablement < ApplicationRecord::Domain::Copilot
      include Repositories::BelongsToRepository

      SETTING_TYPE_VALUES = T.let({
        approval: 0,
        qualified_approval: 1,
      }.transform_keys(&:to_s).freeze, T::Hash[String, Integer])

      enum :setting_type, SETTING_TYPE_VALUES

      self.table_name = "copilot_code_review_repo_enablements"
      self.strict_loading_by_default = true

      validates :owner_id, :repository_id, :setting_type, presence: true

      belongs_to_repository_via_domain class_name: "::Repository", strict_loading: false
      belongs_to :owner, class_name: "::User", strict_loading: false

      sig { params(owner: User).returns(ActiveRecord::Relation) }
      def self.for_repos_owned_by(owner)
        where(owner_id: owner.id)
      end

      sig { params(repository: Repository, setting_type: Symbol).returns(T::Boolean) }
      def self.enabled_for_repository?(repository, setting_type:)
        where(repository_id: repository.id, owner_id: repository.owner_id, setting_type: setting_type_value(setting_type)).exists?
      end

      sig { params(repository_owner: User, setting_type: Symbol).returns(T::Array[::Repository]) }
      def self.enabled_repositories_for_owner(repository_owner, setting_type:)
        raise ArgumentError, "repository_owner must be an organization" unless repository_owner.organization?

        repo_ids = for_repos_owned_by(repository_owner).where(setting_type: setting_type_value(setting_type)).pluck(:repository_id)
        ::Repositories::Public.active_owned_by(repository_owner.id).where(id: repo_ids).to_a
      end

      sig do
        params(
          repository_ids: T::Array[Integer],
          owner: User,
          actor: User,
          setting_type: Symbol,
        ).void
      end
      def self.enable_for_repositories!(repository_ids:, owner:, actor:, setting_type:)
        raise ArgumentError, "owner must be an organization" unless owner.organization?

        normalized_setting_type = setting_type_value(setting_type)

        for_repos_owned_by(owner)
          .where(setting_type: normalized_setting_type)
          .where.not(repository_id: repository_ids)
          .includes(:repository)
          .find_each do |enablement|
            next unless enablement.repository&.adminable_by?(actor)

            enablement.destroy
          end

        ::Repositories::Public.active_owned_by(owner.id).where(id: repository_ids).each do |repository|
          next unless repository.adminable_by?(actor)

          create_or_find_by!(
            repository_id: repository.id,
            owner_id: owner.id,
            setting_type: normalized_setting_type,
          )
        end
      end

      sig { params(setting_type: Symbol).returns(Integer) }
      def self.setting_type_value(setting_type)
        SETTING_TYPE_VALUES.fetch(setting_type.to_s)
      end
    end
  end
end
