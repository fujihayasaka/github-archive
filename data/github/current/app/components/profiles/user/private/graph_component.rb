# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Private
      class GraphComponent < ApplicationComponent
        def initialize(profile_user:)
          @profile_user = profile_user
        end

        private

        attr_reader :profile_user
      end
    end
  end
end
