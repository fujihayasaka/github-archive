# typed: strict
# frozen_string_literal: true

module Growth
  class KeyValueTableExpireJob < BatchedJob
    queue_as :growth_notice_kv_cleanup_expired_data
    retry_on ActiveJob::DeserializationError
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    class GrowthNoticeKeyValues < ApplicationRecord::Domain::UsersCollab
      self.table_name = "growth_notice_key_values"
    end

    BATCH_SIZE = T.let(100, Integer)

    ALLOWED_MODEL_CLASSES = T.let([
      ::Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues.to_s
    ], T::Array[String])

    sig { override.params(batch: ActiveRecord::Relation, args: T.untyped, model_class_str: String, expires_at: Time, options: T.untyped).returns(T.untyped) }
    def process_batch(batch, *args, model_class_str:, expires_at: Time.current, **options)
      ActiveRecord::Base.connected_to(role: :writing) do
        batch.update_all(expires_at: expires_at)
      end
    end

    private

    sig { override.params(args: T.untyped, key: String,  model_class_str: String, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
    def next_batch(*args, key:, model_class_str:, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      GitHub.logger.info("Fetching the next batch of keys to expire",
        "kv.key" => key,
        "kv.model" => model_class_str,
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "offset_item_id" => offset_item_id,
        "progress" => progress,
      )

      raise "Invalid model class" unless ALLOWED_MODEL_CLASSES.include?(model_class_str)
      raise "Invalid key format: #{key}" unless key.match?(/.*\..*\..*/)

      model_class_str.constantize.
      where("`key` LIKE ?", "#{key}%").
      where("id > ?", offset_item_id).
      limit(BATCH_SIZE).
      order(id: :asc)
    end
  end
end
