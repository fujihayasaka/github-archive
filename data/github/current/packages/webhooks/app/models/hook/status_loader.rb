# typed: true
# frozen_string_literal: true

class Hook::StatusLoader

  # Public: For the given Hook records, populate their status attributes.
  #
  # hook_records - Array of Hook records
  #
  # Returns an Array of Hook records
  def self.load_statuses(hook_records: [], parent: nil)
    new(hook_records: hook_records, parent: parent).populate_statuses
  end

  # Public: For a single Hook record, populate it's status.
  #
  # hook_record - A single Hook record
  #
  # Returns the Hook record
  def self.load_status(hook_record)
    load_statuses(hook_records: Array(hook_record)).first
  end

  # Internal
  def initialize(hook_records: [], parent: nil)
    @hook_records = hook_records
    @parent = parent
  end

  # Internal: Retrieve last status for `hook_records` from Hookshot and
  # populate their status attributes.
  #
  # Returns an Array of Hook records
  def populate_statuses
    @hook_records.collect do |hook_record|
      status = hook_statuses[hook_record.id.to_s]
      if status
        hook_record.last_status         = status["status"]
        hook_record.last_status_message = status["response"]
      end
      hook_record
    end
  end

  def hook_statuses
    return {} if @hook_records.empty?
    @statuses ||= hookshot_statuses
  end

  # Internal: Call Hookshot with a single HTTP call for the given `hook_records`.
  #
  # Returns a Hash of {hook_id_as_string => { "status" => code, "response" => message}}
  def hookshot_statuses
    hook_deliveries_client = HookDeliveriesClient.new(first_hook)
    response_code, statuses = hook_deliveries_client.statuses_for_hooks(hook_ids)
    response_code == 200 ? statuses : {}
  end

  # Internal: Convenience method to return an array of IDs from `hook_records`
  def hook_ids
    @hook_records.map(&:id)
  end

  # Internal: The first Hook record. Used to choose the correct
  # Hookshot server.
  def first_hook
    @hook_records.first
  end
end
