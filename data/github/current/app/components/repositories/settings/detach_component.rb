# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    class DetachComponent < ApplicationComponent
      def initialize(repository:)
        @repository = repository
      end

      def self.show_button?(repository)
        repository.fork?
      end

      def enable_button?
        cannot_detach_error.nil?
      end

      private

      attr_reader :repository


      def initial_stage
        2
      end

      memoize def cannot_detach_error
        repository.cannot_detach_repository_reason
      end

      def description
        case cannot_detach_error
        when :not_fork
          "This repository is not a fork."
        when :not_public
          "Only public forks can be detached."
        when :has_forks
          "Can't leave the fork network because this fork has child forks."
        when :too_big
          "Can't detach forks larger than 1 GB."
        when :detach_in_progress
          "Detach is in progress."
        else
          default_description
        end
      end

      def default_description
        "Unlink this repository from the fork network and make it standalone."
      end
    end
  end
end
