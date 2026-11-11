# frozen_string_literal: true

class LabelSettings
  attr_accessor :hold_publication

  # Load and dump are used to provide serializable implementation and to avoid needing to change DB if we want to add more programmatic types.
  def self.load(payload)
    data = JSON.parse(payload || "{}")
    new(data["hold_publication"])
  end

  # This method implicitly defines the JSON schema stored in the DB. This uses Rails native "1" and "0" for true and false, which is weird but ok.
  def self.dump(label_settings)
    JSON.dump(
      "hold_publication" => label_settings.hold_publication,
    )
  end

  # Called when receiving parameters from the web UI, to adapt a Hash POST into an object.
  def self.adapt_params(payload)
    new(payload[:hold_publication])
  end

  def initialize(hold_publication)
    @hold_publication = hold_publication || "0"
  end

  def hold_publication?
    hold_publication == "1"
  end
end
