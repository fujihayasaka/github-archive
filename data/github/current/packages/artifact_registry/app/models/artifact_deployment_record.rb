# typed: true
# frozen_string_literal: true

class ArtifactDeploymentRecord < ApplicationRecord::Domain::ArtifactRegistry
  belongs_to :artifact_metadata, inverse_of: :deployment_records

  validates :logical_environment, length: { maximum: 64 }
  validates :physical_environment, length: { maximum: 64 }
  validates :cluster, length: { maximum: 64 }
  validates :deployment_name, length: { maximum: 128 }

  scope :active, -> {
    where(deleted_at: nil)
  }

  def deployed?
    deleted_at.nil?
  end

  def decommissioned?
    deleted_at.present?
  end

  def decommission(time = Time.now)
    self.update!(deleted_at: time)
  end

  has_many :deployment_record_tags,
    class_name: "ArtifactDeploymentRecordTag",
    foreign_key: :deployment_record_id,
    inverse_of: :deployment_record,
    dependent: :destroy

  validates_length_of :deployment_record_tags, maximum: 5

  # Only for automatic active record creation
  def tags=(tags)
    return unless tags.present?

    tag_params = convert_tags_to_table_format(tags)
    deployment_record_tags.build(tag_params)
  end

  def create_tags(tags)
    return unless tags.present?

    tag_params = convert_tags_to_table_format(tags)
    deployment_record_tags.create(tag_params)
  end

  def update_tags(tags)
    return unless tags.present?

    tag_params = convert_tags_to_table_format(tags)

    deployment_record_tags.destroy_all
    deployment_record_tags.create(tag_params)
  end

  # Simplified version to match the input options above
  # If you want the full database values, use deployment_record_tags
  def tags
    deployment_record_tags.map { |tag| [tag.tag_name, tag.tag_value] }.to_h
  end

  private

  def convert_tags_to_table_format(tags)
    tags.map do |k, v|
      { tag_name: k, tag_value: v }
    end
  end
end
