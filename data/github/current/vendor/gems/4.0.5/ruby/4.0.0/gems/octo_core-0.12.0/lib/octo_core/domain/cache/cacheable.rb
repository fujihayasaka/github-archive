# typed: strict
# frozen_string_literal: true

module OctoCore
  module Domain
    class Cache
      module Cacheable
        extend T::Sig
        extend T::Helpers

        include Kernel

        interface!

        # This identifier is required to be unique across an instance of OctoCore::Domain::Base!
        # A domain class should only act on one type of ActiveRecord model, if not,
        # ActiveRecord::Base#id will conflict. Instead, we favor splitting the domain
        # into multiple accessors for each type.
        #
        # e.g. (bad!)
        # class MyDomain < OctoCore::Domain::Base
        #   sig { returns(Repository) }
        #   def repository_by_id(id); end
        #   sig { returns(KeyLink) }
        #   def key_link_by_id(id); end
        # end
        sig { abstract.returns(Integer) }
        def id
        end

        sig { abstract.returns(OctoCore::Domain::Base) }
        def domain
        end

        sig { abstract.returns(Cacheable) }
        def duplicate
        end
      end
    end
  end
end
