# typed: strict
# frozen_string_literal: true

module KeyLinks
  module Public
    # provide access to throller methods through the public API
    class Throttler < ApplicationRecord::Collab; end
  end
end
