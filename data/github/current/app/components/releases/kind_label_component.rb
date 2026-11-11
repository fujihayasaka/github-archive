# typed: true
# frozen_string_literal: true

module Releases
  class KindLabelComponent < ApplicationComponent
    def initialize(release, repository, is_latest:, **system_arguments)
      @release = release
      @current_repository = repository
      @is_latest = is_latest
      @system_arguments = system_arguments
    end

    attr_reader :release, :current_repository

    def call
      if release.draft?
        render(T.unsafe(Primer::Beta::State).new(title: "Draft", size: :small, vertical_align: :text_bottom, **@system_arguments)) { "Draft" }
      elsif @is_latest
        render Primer::Beta::Link.new(href: latest_release_path(current_repository.owner, current_repository), vertical_align: :text_bottom, **@system_arguments) do
          render(Primer::Beta::Label.new(scheme: :success, size: :large)) { "Latest" }
        end
      elsif release.prerelease?
        render(Primer::Beta::Label.new(scheme: :warning, size: :large, vertical_align: :text_bottom, **@system_arguments)) { "Pre-release" }
      end
    end
  end
end
