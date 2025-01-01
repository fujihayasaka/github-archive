# typed: true
# frozen_string_literal: true

class Attachment < ApplicationRecord::Domain::Assets

  belongs_to :asset, class_name: "UserAsset"
  belongs_to :entity, polymorphic: true
  belongs_to :attacher, class_name: "User"
  belongs_to :attachable, polymorphic: true
  before_validation :denormalize_attachable, on: :create
  after_create_commit :instrument_creation # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Public: Attach one or more Asset objects to an attachable comment.
  #
  # attachable    - A comment record, such as an IssueComment, that includes
  #                 GitHub::UserContent.
  # asset_matches - Array of AssetScanner::Match objects. See:
  #                 GitHub::UserContent#attach_matching_assets
  #
  # Returns nothing.
  def self.attach(attachable, asset_matches)
    assets = UserAsset.from_matches(asset_matches)
    attached_ids = assets.map { |a| a.id }
    attached_ids.uniq!
    existing_ids = attachable.attachments.reload.map { |att| att.asset_id }

    attach_user_asset_ids(attachable, attached_ids - existing_ids)
    detach_old_user_asset_ids(attachable, existing_ids - attached_ids)
  end

  def self.attach_user_asset_ids(attachable, asset_ids)
    return if asset_ids.blank?
    now = attachable.send(:current_time_from_proper_timezone)
    all_values = asset_ids.map do |asset_id|
      [attachable.user_id, asset_id, attachable.id, attachable.class.base_class.name,
      now, now, attachable.entity.id, attachable.entity.class.base_class.name]
    end

    all_values.each_slice(100) do |batch|
      sql_bindings = {
        values: Arel::Nodes::ValuesList.new(batch),
        updated_at: attachable.send(:current_time_from_proper_timezone),
      }
      sql = Arel.sql <<-SQL, **sql_bindings
        INSERT INTO `attachments`
          (`attacher_id`, `asset_id`, `attachable_id`, `attachable_type`,
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

  def self.detach_old_user_asset_ids(attachable, asset_ids)
    return if asset_ids.blank?
    # demand a write connection to avoid https://github.com/github/issues-platform/issues/174
    ActiveRecord::Base.connected_to(role: :writing) do
      where(attachable_id: attachable.id,
        attachable_type: attachable.class.name, asset_id: asset_ids).delete_all
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
