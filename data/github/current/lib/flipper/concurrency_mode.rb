# typed: true
# frozen_string_literal: true

# Extends Flipper::Feature such that it has access to
# GitHub Feature's rollout_updated_at and a should_compare_etag
# These are used to determine if the feature has changed when doing
# an enable/disable inside of the mysql adapter.
#
# A note on this implementation:
# This is based on the implementation of lib/flipper/employee_mode.rb.
module Flipper
  # The ConcurrencyMode module is prepended to Flipper::Feature itself
  module ConcurrencyMode
    attr_accessor :rollout_updated_at, :should_compare_etag
  end

  # Wraps GitHub's FlipperFeature methods to set rollout_updated_at and should_compare_etag
  # so that we can check if the gates have changed since the last update
  module ConcurrencyProxy
    def rollout_updated_at_proxy(*method_names)
      T.bind(self, Module)
      proxy = Module.new do
        method_names.each do |method_name|
          define_method(method_name) do |*args, &block|
            begin
              if self.instance_variable_defined?(:@should_compare_etag) && self.instance_variable_get(:@should_compare_etag)
                current_user = User.find_by(id: GitHub.context[:actor_id])
                @raw_feature ||= GitHub.flipper[T.unsafe(self).name.to_sym]
                @raw_feature.rollout_updated_at = T.unsafe(self).rollout_updated_at
                @raw_feature.should_compare_etag = self.instance_variable_get(:@should_compare_etag)
              end
              super(*args, &block)
            ensure
              # Make sure to remove the concurrency mode attributes once this method has run so it doesn't persist on the memoized raw_feature
              @raw_feature ||= GitHub.flipper[T.unsafe(self).name.to_sym]
              @raw_feature.rollout_updated_at = nil
              @raw_feature.should_compare_etag = nil
            end
          end
        end
      end
      self.prepend proxy
    end
  end
end

Flipper::Feature.prepend(Flipper::ConcurrencyMode)
