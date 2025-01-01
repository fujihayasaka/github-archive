# typed: true
# frozen_string_literal: true

class Copilot::CopilotApi::TrackingIdActor
  include GitHub::FlipperActor
  include GitHub::VexiActor

  # Necessary to tell the feature Twirp API how to
  # find the actor from the flipper_id. In this case,
  # we just want a new instance of this class with the
  # tracking_id passed in.
  def self.find_by_id(tracking_id) # rubocop:disable GitHub/FindByDef
    new(tracking_id)
  end

  def initialize(tracking_id)
    @tracking_id = tracking_id
  end

  def flipper_id
    "#{self.class.name}:#{@tracking_id}"
  end

  def vexi_id
    flipper_id
  end
end
