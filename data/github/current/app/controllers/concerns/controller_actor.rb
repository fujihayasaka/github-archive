# typed: strict
# frozen_string_literal: true

# Vexi actor identifying a specific controller class. Used to scope a single
# shared feature flag (e.g. :web_read_from_replicas_controller) per controller without
# having to declare a dedicated flag per call site.
class ControllerActor
  include GitHub::VexiActor

  sig { params(id: String).returns(ControllerActor) }
  def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
    new(id)
  end

  sig { params(controller_class: T.any(String, T.class_of(ApplicationController))).void }
  def initialize(controller_class)
    name = controller_class.is_a?(String) ? controller_class : controller_class.name
    @vexi_id = T.let("#{self.class.name}:#{name}", String)
  end

  sig { returns(String) }
  def to_s
    @vexi_id
  end

  sig { returns(String) }
  def vexi_id
    @vexi_id
  end
end
