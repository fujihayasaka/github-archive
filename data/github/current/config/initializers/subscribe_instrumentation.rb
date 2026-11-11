# frozen_string_literal: true

unless Rails.env.test?
  require "instrumentation_subscribers/user_asset"
  InstrumentationSubscribers::UserAsset.attach!

  require "instrumentation_subscribers/hook"
  InstrumentationSubscribers::Hook.attach!

  require "instrumentation_subscribers/release_asset"
  InstrumentationSubscribers::ReleaseAsset.attach!

  require "instrumentation_subscribers/repository_file"
  InstrumentationSubscribers::RepositoryFile.attach!
end
