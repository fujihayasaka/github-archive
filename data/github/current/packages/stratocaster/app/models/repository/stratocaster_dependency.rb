# typed: false
# frozen_string_literal: true

module Repository::StratocasterDependency
  include Stratocaster::EventTarget

  # Public: Generates the Stratocaster event key for Repositories.
  #
  # :type - A Symbol identifying a sub type, or nil.
  #         :issues  - The Repository issues feed.
  #         :network - The feed of public actions for repositories in the same
  #                    network.
  #
  # Returns a String key.
  def events_key(options = {})
    case options[:type]
    when :issues then "repo:#{id}:issues"
    when :network then "network:#{network_id}:public"
    when nil then "repo:#{id}"
    else
      raise ArgumentError, "Invalid :type"
    end
  end
end
