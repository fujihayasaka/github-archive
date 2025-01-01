module Dependency
  def self.included(base)
    base.restrict_type_of :scope, to: Types::Scope
    base.extend ClassMethods
  end

  def package
    Package.for_package_manager(package_manager).with_name(package_name).first
  end

  module ClassMethods
    def runtime
      where(scope: Types::Scope[:runtime].serialize)
    end

    def development
      where(scope: Types::Scope[:development].serialize)
    end

    def with_alphabetical_package_name
      order(package_name: :asc)
    end

    def for_package_manager(package_manager)
      where(package_manager: package_manager.serialize)
    end

    def with_package_name(package_name)
      where(package_name: package_name)
    end
  end
end
