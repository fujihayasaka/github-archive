# typed: strict
# frozen_string_literal: true

class DeleteRepositoryFilesByUserIdJob < BatchedJob
  queue_as :delete_user_attachments
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(files_batch: T::Array[RepositoryFile], args: T.untyped, options: T.untyped).void }
  def process_batch(files_batch, *args, **options)
    files_batch.each do |file|
      RepositoryFile.throttle do
        with_write { file.destroy }
      end
    end
  end

  # expecting options to have:
  # :user_id as user id (integer - required)
  # :files_ids array of repository_files ids (integers - optional)
  sig do
    params(
      args: T.untyped,
      timestamp: T.nilable(Time),
      offset_item_id: T.nilable(Integer),
      options: T.untyped,
    ).returns(T::Array[RepositoryFile])
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, **options)
    RepositoryFile
      .where(uploader_id: options[:user_id])
      .then { |scope| options[:files_ids].present? ? scope.where(id: options[:files_ids]) : scope }
      .where("id > ?", offset_item_id)
      .order(id: :asc)
      .limit(BATCH_SIZE)
      .to_a
  end
end
