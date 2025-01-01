# typed: true
# frozen_string_literal: true

class Attachment < ApplicationRecord::Domain::AssetObjects

  belongs_to :asset, polymorphic: true
  belongs_to :entity, polymorphic: true
  belongs_to :attacher, class_name: "User"
  belongs_to :attachable, polymorphic: true
  before_validation :denormalize_attachable, on: :create
  after_create_commit :instrument_creation # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Public: Attach one or more Asset objects to an attachable comment.
  #
  # attachable            - A comment record, such as an IssueComment, that includes
  #                         GitHub::UserContent.
  # asset_matches         - Array of AssetScanner::Match objects. See:
  #                         GitHub::UserContent#attach_matching_assets
  # detach_removed_assets - Boolean indicating whether to detach old assets no longer
  #                         present in the list of matches. Defaults to true
  #
  # Returns nothing.
  def self.attach(attachable, asset_matches, detach_removed_assets: true, attaching_user: nil)
    attach_for_asset_type(attachable, asset_matches, UserAsset, detach_removed_assets, attaching_user)

    # Repository Files can ONLY be attached within a Repository context
    attach_for_asset_type(attachable, asset_matches, RepositoryFile, detach_removed_assets, attaching_user) if attach_repository_files?(attachable.entity)
  end

  def self.attach_repository_files?(entity)
    return false if entity.nil?
    entity.class.base_class == Repository && FeatureFlag.vexi.enabled_or_raise?(:attach_repository_files) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def self.attach_for_asset_type(attachable, asset_matches, asset_type, detach_removed_assets, attaching_user)
    assets = asset_type.from_matches(asset_matches)
    attached_ids = assets.map { |a| a.id }
    attached_ids.uniq!
    existing_ids = Attachment.where(attachable: attachable, asset_type: asset_type.name).pluck(:asset_id)

    attach_asset_ids(attachable, attached_ids - existing_ids, attaching_user, asset_type.name)
    detach_old_asset_ids(attachable, existing_ids - attached_ids, asset_type.name) if detach_removed_assets
  end

  def self.attach_asset_ids(attachable, asset_ids, attaching_user, asset_type)
    return if asset_ids.blank?
    now = attachable.send(:current_time_from_proper_timezone)
    all_values = asset_ids.map do |asset_id|
      [attacher_id(attachable, attaching_user), asset_id, asset_type, attachable.id, attachable.class.base_class.name,
      now, now, attachable.entity.id, attachable.entity.class.base_class.name]
    end

    all_values.each_slice(100) do |batch|
      sql_bindings = {
        values: Arel::Nodes::ValuesList.new(batch),
        updated_at: attachable.send(:current_time_from_proper_timezone),
      }
      sql = Arel.sql <<-SQL, **sql_bindings
        INSERT INTO `attachments`
          (`attacher_id`, `asset_id`, `asset_type`, `attachable_id`, `attachable_type`,
           `created_at`, `updated_at`, `entity_id`, `entity_type`)
        :values
        ON DUPLICATE KEY UPDATE `updated_at` = :updated_at
      SQL
      # demand a write connection to avoid https://github.com/github/issues-platform/issues/174
      ActiveRecord::Base.connected_to(role: :writing) do
        self.connection.insert(sql)
      end
    end
  end

  def self.detach_old_asset_ids(attachable, asset_ids, asset_type)
    return if asset_ids.blank?
    # demand a write connection to avoid https://github.com/github/issues-platform/issues/174
    ActiveRecord::Base.connected_to(role: :writing) do
      where(attachable_id: attachable.id,
        attachable_type: attachable.class.name, asset_id: asset_ids, asset_type: asset_type).delete_all
    end
  end

  def self.asset_ids_for_entity(entity)
    Attachment.where(entity: entity).pluck(:asset_id)
  end

  def self.user_assets_for_entity(entity)
    UserAsset.where(id: asset_ids_for_entity(entity))
  end

  def self.attacher_id(attachable, attaching_user)
    return attaching_user.id if attaching_user

    case attachable
    when DraftIssue
      attachable.creator.id
    when Gist
      if attachable.anonymous?
        User.ghost.id
      else
        attachable.user_id
      end
    when RepositoryWiki
      # This is here as a fallthrough but we should never hit this case -
      # Wiki attachments should always pass through an attaching user
      T.must(T.must(attachable.repository).owner).id
    when Repository
      # This is here as a fallthrough but we should never hit this case -
      # Repository attachments should always pass through an attaching user
      T.must(attachable.owner).id
    else
      attachable.user_id
    end
  end

  def denormalize_attachable
    self.entity = attachable.entity
    T.unsafe(self).attacher_id ||= attachable.user_id
  end

  def instrument_creation
    instrument :attachment
  end

  include Instrumentation::Model
  def event_prefix() :assets end
end
