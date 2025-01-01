# typed: true
# frozen_string_literal: true

class MemexProjectItemSetColumnsJob < ApplicationJob
  queue_as :memex_project_item_set_columns

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 5.minutes, key: ->(job) {
    job.arguments[0]
  }

  MAX_THROTTLE_RETRIES = 5
  METRIC_INDEX = "memex_project_item_set_columns_job"

  def perform(item_id, column_list, creator_id)
    creator = User.find_by(id: creator_id)
    memex_item = MemexProjectItem.find_by(id: item_id)

    return log("status:404", "error:invalid:user") unless creator
    return log("status:404", "error:invalid:item") unless memex_item

    log("status:202", "item:set_column_values")
    with_write_values do
      column_list.each do |column_data|
        column = column_data[:column]
        value = column_data[:value]
        value_update_success = memex_item.set_column_value(column, value, creator)

        log(value_update_success ? "status:201" : "status:422", "item:set_column_value")
        log_set_field(
          item_id: item_id,
          actor_id: creator_id,
          column: column, value: value,
          result: value_update_success ? "success" : "failure"
        )
      end
    end
  end

  private

  # Simple wrapper for connecting to write pool for write operations only.
  def with_write_values
    ActiveRecord::Base.connected_to(role: :writing) do
      MemexProjectColumnValue.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        yield
      end
    end
  end

  def log(status, reason = "")
    GitHub.dogstats.increment(
      METRIC_INDEX,
      tags: reason ? [status, reason] : [status]
    )
  end

  def log_set_field(**params)
    if Rails.env.development?
      Rails.logger.debug("#{self.class.name}: #{params}")
    else
      GitHub.logger.info(
            "code.namespace": self.class.name,
            "gh.actor.id": params[:actor_id],
            "gh.memex.item.id": params[:item_id],
            "gh.memex.column.id": params[:column]&.id || "",
            "gh.memex.column.value": params[:value],
            "gh.memex.column.update_result": params[:result]
          )
    end
  end
end
