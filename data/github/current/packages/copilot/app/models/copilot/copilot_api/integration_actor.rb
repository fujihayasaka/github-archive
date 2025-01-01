# typed: true
# frozen_string_literal: true

class Copilot::CopilotApi::IntegrationActor
  include GitHub::FlipperActor
  include GitHub::VexiActor

  # Necessary to tell the feature Twirp API how to
  # find the actor from the flipper_id. In this case,
  # we just want a new instance of this class with the
  # integration_id passed in.
  def self.find_by_id(integration_id) # rubocop:disable GitHub/FindByDef
    new(integration_id)
  end

  def initialize(integration_id)
    @integration_id = integration_id
  end

  def flipper_id
    "#{self.class.name}:#{@integration_id}"
  end

  def vexi_id
    flipper_id
  end
end
