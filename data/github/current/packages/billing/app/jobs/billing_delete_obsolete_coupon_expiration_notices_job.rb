# typed: true
# frozen_string_literal: true

require "github/sql/readonly"

class BillingDeleteObsoleteCouponExpirationNoticesJob < BillingJob
  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  def perform
    user_ids_with_deleted_notices = []

    user_id_iterator.batches.each do |rows|
      user_ids = rows.flatten
      users = User.where(id: user_ids)
      GitHub::PrefillAssociations.prefill_batch_method(users, :coupon_redemption)

      users_with_obsolete_notices =
        users.reject do |user|
          user.has_an_active_coupon? &&
            user.paid_plan? &&
            user.coupon_redemption&.expires_this_billing_cycle?
        end

      users_with_obsolete_notices.each do |user|
        user.throttle_writes do
          user.delete_notice(:coupon_will_expire)
        end
        user_ids_with_deleted_notices << user.id
      end
    end

    GitHub.dogstats.gauge(
      "dashboard_notices.obsolete_coupon_expiration_notices_deleted",
      user_ids_with_deleted_notices.size,
    )

    user_ids_with_deleted_notices
  end

  private

  def user_id_iterator
    GitHub::QueryBatching::IteratorBuilder.new(batch_size: 1_000) do |iteration|
      batch = ApplicationRecord::Domain::Users.connection.select_rows(Arel.sql(<<-SQL, **iteration.cursor.arel_bindings))
        SELECT `dashboard_notices`.`id`, `dashboard_notices`.`user_id`
        FROM `dashboard_notices`
        WHERE `dashboard_notices`.`notice_name` = "coupon_will_expire"
          AND `dashboard_notices`.`id` >= :lower_id
        ORDER BY `dashboard_notices`.`id`
        LIMIT :limit
      SQL

      # Yield only the user_id
      iteration << batch.map { |b| [b.last] }

      # Make sure the last ID is from the dashboard_notices IDs, not the user IDs yielded
      iteration.last_id = batch.last&.first
    end
  end
end
