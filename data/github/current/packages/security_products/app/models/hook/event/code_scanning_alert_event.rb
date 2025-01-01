# typed: true
# frozen_string_literal: true

require "turboscan"

class Hook::Event::CodeScanningAlertEvent < Hook::Event
  supports_targets(*DEFAULT_TARGETS)

  description "Code Scanning alert created, fixed in branch, or closed"

  event_attr :action, :repository_id, :alert_number, required: true
  event_attr :commit_oid, :ref, :actor_id, :result

  def deliverable?
    target_repository.present?
  end

  def target_repository
    @repository ||= Repositories.domain.by_id(repository_id)
  end

  def target_organization
    owner = target_repository&.owner
    owner&.organization? ? owner : nil
  end

  def alert
    return @alert if defined? @alert
    return nil unless result

    begin
      @alert = Turboscan::Proto::Result.new(result)
    rescue ArgumentError
      # This code should not be needed under normal conditions but if changes are made to the Result
      # format then during deployment an event created by the old code running in production might get
      # executed by the new code running in canary.
      # This restricts the result to the fields that are expected by the current code which prevents
      # the initializer further below from raising exceptions on removed (or not yet released) fields.
      check_instance = Turboscan::Proto::Result.new({
        rule: Turboscan::Proto::Rule.new,
        tool: Turboscan::Proto::ToolDescription.new,
        most_recent_instance: Turboscan::Proto::AlertInstance.new({ analysis_key: Turboscan::Proto::AnalysisKey.new, location: Turboscan::Proto::Location.new })
      })
      safe_result = get_twirp_safe_hash(check_instance, result)

      # The payload serializer currently expects a Twirp response, so we need to make sure we send it the info in the correct format
      @alert = Turboscan::Proto::Result.new(safe_result)
    end
  end

  def get_twirp_safe_hash(check_instance, data)
    if data.nil?
      return
    end
    safe_data = {}
    data.each do |k, v|
      if check_instance.respond_to?(k)
        safe_data[k] = v
        check_value = check_instance.send(k)
        if check_value.class.name.starts_with?("Turboscan::Proto::")
          safe_data[k] = get_twirp_safe_hash(check_value, v)
        end
      end
    end
    safe_data
  end

  def actor
    return @actor if defined? @actor
    if actor_id.present?
      @actor = User.find_by(id: actor_id)
    elsif GitHub.enterprise?
      @actor = User.find_by(login: "github-enterprise")
    else
      @actor = User.find_by(login: "github")
    end
  end
end
