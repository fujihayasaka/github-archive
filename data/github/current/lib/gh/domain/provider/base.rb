# typed: true
# frozen_string_literal: true

module GH
  module Domain
    module Provider
      module Base
        def self.included(othermod)
          othermod.module_eval do
            def self.included(othermod)
              if othermod.singleton_class?
                raise "Domain Providers should not be extended. Include them instead."
              end
              super
            end

            def self.extended(othermod)
              raise "Domain Providers should not be extended. Include them instead."
            end
          end
        end
      end
    end
  end
end
