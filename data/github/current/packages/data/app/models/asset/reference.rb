# typed: true
# frozen_string_literal: true

# Joins an Asset with the uploadable model that uses it.  Mostly kept for
# auditing purposes.
class Asset::Reference < ApplicationRecord::Domain::Assets

  belongs_to :asset
  belongs_to :uploadable, polymorphic: true

  validates_presence_of :asset_id, :uploadable_id, :uploadable_type

  # Internal: Removes any Asset::References for the following asset and all of
  # the given uploadables.
  #
  # Note: not run inside a transaction.  This should be run from the
  # transaction in Asset#purge!.
  def self.purge(asset, uploadables)
    uploadables.each do |uploadable|
      # matches on a unique index
      where(
        uploadable_id: uploadable.id,
        uploadable_type: uploadable.class.base_class.name,
        asset_id: asset.id,
      ).delete_all
    end
  end
end
