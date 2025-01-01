# typed: true
# frozen_string_literal: true

module GitHub
  module AssociationInstrumenter
    KEY = :"GitHub::AssociationInstrumenter.callback"

    module Ext
      # The `async` argument comes from ActiveRecord::Associations::Association#load_target but is not used in this method.
      def find_target(...)
        if callback = Thread.current[KEY]
          callback.call(self)
        end

        super
      end
    end

    def self.track_loads(callback)
      old_callback, Thread.current[KEY] = Thread.current[KEY], callback
      yield
    ensure
      Thread.current[KEY] = old_callback
    end
  end
end

ActiveRecord::Associations::HasManyThroughAssociation.prepend(GitHub::AssociationInstrumenter::Ext)
ActiveRecord::Associations::CollectionAssociation.prepend(GitHub::AssociationInstrumenter::Ext)
ActiveRecord::Associations::SingularAssociation.prepend(GitHub::AssociationInstrumenter::Ext)
