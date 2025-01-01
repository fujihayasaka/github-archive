# typed: strict
# frozen_string_literal: true

class DeleteUserAssetsByUserIdJob < BatchedJob
  queue_as :delete_user_attachments
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(assets_batch: T::Array[UserAsset], args: T.untyped, options: T.untyped).void }
  def process_batch(assets_batch, *args, **options)
    assets_batch.each do |asset|
      UserAsset.throttle do
        with_write { asset.purge }
      end
    end
  end

  # expecting options to have:
  # :user_id as user id (integer - required)
  # :assets_ids array of user_assets ids (integers - optional)
  sig do
    params(
      args: T.untyped,
      timestamp: T.nilable(Time),
      offset_item_id: T.nilable(Integer),
      options: T.untyped,
    ).returns(T::Array[UserAsset])
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, **options)
    UserAsset
      .where(user_id: options[:user_id])
      .then { |scope| options[:assets_ids].present? ? scope.where(id: options[:assets_ids]) : scope }
      .where("id > ?", offset_item_id)
      .order(id: :asc)
      .limit(BATCH_SIZE)
      .to_a
  end
end
