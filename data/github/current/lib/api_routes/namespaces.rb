# typed: true
# frozen_string_literal: true
module ApiRoutes
  # Collect all the namespaces with their routes under a single top-level namespace.
  class Namespaces
    def self.in(namespace, collector: DefaultCollector, filter:, public_only: false)
      collections = []
      namespace.descendants.each do |descendant|
        next if filter.present? && filter != descendant.to_s

        if public_only
          excluded_prefixes = %w(Api::Enterprise)

          excluded_classes = %w(
            Api::Internal
            Api::Staff
            Api::Admin
            Api::ThirdParty
          )
          next if excluded_classes.detect { |pc| descendant.to_s == pc || descendant.superclass.to_s.starts_with?(pc)  }
          next if excluded_prefixes.detect { |ns| descendant.to_s.starts_with?(ns)  }
        end

        collection = Collection.new(descendant)
        collection.add collector.endpoints_in(descendant)
        collection.endpoints.sort!.uniq!(&:to_s)
        collections << collection unless collection.none?
      end
      collections.sort_by!(&:namespace)
      collections
    end
  end
end
