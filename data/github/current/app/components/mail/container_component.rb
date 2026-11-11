# typed: true
# frozen_string_literal: true

# Use this for creating a full width container in HTML emails.
# Based off of Inky's implementation: https://get.foundation/emails/docs/grid.html#container
#
# Adjusted to work properly with Primer.
class Mail::ContainerComponent < ApplicationComponent
  attr_reader :classes

  def initialize(classes: nil)
    @classes = class_names("width-full", classes)
  end
end
