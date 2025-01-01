# typed: true
# frozen_string_literal: true

##
# Abstract class for defining a Service Class
#
# Subclass from this to create a new Service Class, following the naming convention
# of VerbNoun. (eg AcceptInvitation or DownloadArchive)
#
# Implement the `#initialize` method to set up attributes, and a `#call` instance
# method to define the functionality of your Service Class.
#
# Use your Service Class by calling `.call`, like so:
#
#     AcceptInvitation.call(user, invitation)
#
# Arguments passed to `.call` will be automatically forwarded to `#initialize`
#
# More info at https://brewhouse.io/blog/2014/04/30/gourmet-service-objects.html
#
#
module Octoshift
  module Service
    class Base
      def self.call(*args, **kargs)
        T.unsafe(self).new(*args, **kargs).call
      end

      def initialize(*, **); end

      def call
        raise NotImplementedError, "Must implement #call in #{self.class.name}"
      end
    end
  end
end
