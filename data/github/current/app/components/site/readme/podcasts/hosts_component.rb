# typed: true
# frozen_string_literal: true

class Site::Readme::Podcasts::HostsComponent < ApplicationComponent
  include Site::ReadmeHelper

  def initialize(hosts:)
    @hosts = hosts
  end
end
