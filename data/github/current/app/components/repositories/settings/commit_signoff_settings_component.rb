# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    class CommitSignoffSettingsComponent < ApplicationComponent
      attr_accessor :repo

      def initialize(repository)
        @repo = repository
      end
    end
  end
end
