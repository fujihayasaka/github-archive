# typed: true
# frozen_string_literal: true

# Use this for creating vertical space in an HTML email.
# Replicates Inky's implementation: https://get.foundation/emails/docs/spacer.html
class Mail::SpacerComponent < ApplicationComponent
  attr_reader :size

  def initialize(size: 16)
    @size = size
  end
end
