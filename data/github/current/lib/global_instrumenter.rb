# typed: true
# frozen_string_literal: true

# The GlobalInstrumenter was introduced as an alternative to `GitHub.instrument`,
# `Instrumentation::Model#instrument`, and `GitHub.subscribe` as their primary use is for
# instrumenting events that will be saved to the audit log. See the following issue for more
# details: https://github.com/github/data-engineering/issues/561
# Note: Looking for adding webhook events? Checkout https://thehub.github.com/engineering/development-and-ops/dotcom/webhooks/#so-you-want-to-build-a-new-hook-event
#  ...Webhook events are backed by in-memory `ActiveSupport::Notifications`, whereas
#  ...GlobalInstrumenter is for hydro logging. For webhook you should only need `GitHub::instrument`
# The goals of this instrumenter are:
#   * Make no assumptions about the payload or what the subscribers expect and therefore make no
#     modifications to the payload.
#   * Operate separately from the legacy instrumenter as it has been tailored for publishing events
#     to the audit log.
#
# Usage:
#
#  > class Foo
#      def bar
#        GlobalInstrumenter.instrument "foo.bar", { foo: self }
#      end
#    end
# => :bar
#  > foo = Foo.new
# => #<Foo:0x00007fc5dc5e7cf8>
#  > GlobalInstrumenter.subscribe("foo.bar") { |name, _, _, _, payload| puts name, payload }
# => #<ActiveSupport::Notifications::Fanout::Subscriber:0x00007fc5dc5f7810 @pattern="global.foo.bar", @delegate=#<Proc:0x00007fc5dc5f78b0@(irb):7>>
#  > foo.bar
# global.foo.bar
# {:foo=>#<Foo:0x00007fc5dc5e7cf8>}
# => nil
#

require "github/config/notifications"

module GlobalInstrumenter
  class << self
    attr_accessor :notifier, :instrumenter
  end

  def self.instrument(name, payload = {})
    if notifier.listening?(name) && !Instrumentation.suppressed?
      instrumenter.instrument(name, payload) { yield payload if block_given? }
    else
      yield payload if block_given?
    end
  end

  def self.subscribe(*args, &block)
    notifier.subscribe(*args, &block)
  end

  self.notifier = ActiveSupport::Notifications::Fanout.new
  self.instrumenter = ActiveSupport::Notifications::Instrumenter.new(notifier)
end
