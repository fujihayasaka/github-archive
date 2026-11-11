# typed: strict
# frozen_string_literal: true

module GH
  module Domain
    class Cache
      module Cachable
        extend T::Helpers

        include Kernel

        interface!

        # This identifier is required to be unique across an instance of GH::Domain::Base!
        # A domain class should only act on one type of ActiveRecord model, if not,
        # ActiveRecord::Base#id will conflict. Instead, we favor splitting the domain
        # into multiple accessors for each type.
        #
        # e.g. (bad!)
        # class MyDomain < GH::Domain::Base
        #   sig { returns(Repository) }
        #   def repository_by_id(id); end
        #   sig { returns(KeyLink) }
        #   def key_link_by_id(id); end
        # end
        sig { abstract.returns(Integer) }
        def id; end

        sig { abstract.returns(GH::Domain::Base) }
        def domain; end

        sig { abstract.returns(Cachable) }
        def duplicate; end
      end
    end
  end
end
