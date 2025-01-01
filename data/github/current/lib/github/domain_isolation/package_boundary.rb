# typed: true
# frozen_string_literal: true

module GitHub
  module DomainIsolation
    # Deprecated: Don't use this module anymore. Instead check out the new domain isolation
    #   tooling in `lib/gh`: https://github.com/github/github/tree/master/lib/gh
    #
    # Once all references to this module are removed, we remove it.
    #   https://github.com/github/app-partitioning/issues/181
    #
    module PackageBoundary
      def self.extended(base_class)
        wrapper = Module.new do
          base_class.public_methods
              .select { |method_name| base_class.method(method_name).owner == base_class }
              .each do |method_name|
            define_method(method_name) do |*args, **kwargs, &block|
              GitHub::DomainIsolation.within_domain_of(base_class) { super(*args, **kwargs, &block) }
            end
          end
        end

        base_class.extend(wrapper)
      end
    end
  end
end
