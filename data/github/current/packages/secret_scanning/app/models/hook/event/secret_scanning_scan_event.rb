# typed: true
# frozen_string_literal: true

class Hook::Event::SecretScanningScanEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets(*DEFAULT_TARGETS)

  description "Secrets scanning scan completed."

  event_attr :repository_id,
    :source,
    :type,
    :source_slug,
    :type_slug,
    :started_at,
    :completed_at,
  required: true

  # If we are working with a scan for pattern updates,
  # include the secret types.
  event_attr :secret_types

  # If we are working with a scan for a custom pattern backfill,
  # include custom pattern details
  event_attr :custom_pattern_name, :custom_pattern_scope

  def action
    :completed
  end

  def target_repository
    @repository ||= with_read { Repository.find_by(id: repository_id) }
  end

  def actor
    User.ghost
  end

  def pattern_update_backfill?
    type == :TYPE_PATTERN_VERSION_BACKFILL
  end

  def custom_pattern_backfill?
    type == :TYPE_CUSTOM_PATTERN_BACKFILL
  end

  def deliverable?
    target_repository.present?
  end

  private

  def with_read
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end
end
