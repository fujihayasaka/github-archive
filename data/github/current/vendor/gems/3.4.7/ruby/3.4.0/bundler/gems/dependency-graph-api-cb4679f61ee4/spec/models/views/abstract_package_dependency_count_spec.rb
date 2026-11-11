require "rails_helper"

module Views
  describe AbstractPackageDependencyCount do
    let!(:react_ruby) do
      factory.given_package("react", "1.0.0")
        .update_package(package_manager: :rubygems)
        .package
    end

    let!(:react_js) do
      factory.given_package("react", "1.0.0")
        .update_package(package_manager: :npm)
        .package
    end

    describe ".rebuild" do
      it "counts repository abstract dependencies" do
        create_ruby_dependency("react", dependent_id: 1)
        create_ruby_dependency("react", dependent_id: 2)

        create_npm_dependency("react", dependent_id: 1)
        create_npm_dependency("react", dependent_id: 2)
        create_npm_dependency("react", dependent_id: 3)

        described_class.rebuild

        expect(described_class.count).to eq 2
        expect(described_class.for(react_ruby)).to eq 2
        expect(described_class.for(react_js)).to eq 3
      end
    end

    describe ".update" do
      it "incrementally builds counts" do
        expect(described_class.count).to eq 0
        expect(described_class.for(react_ruby)).to eq 0
        expect(described_class.for(react_js)).to eq 0

        create_ruby_dependency("react", dependent_id: 1)
        create_npm_dependency("react", dependent_id: 1)

        described_class.update

        expect(described_class.count).to eq 2
        expect(described_class.for(react_ruby)).to eq 1
        expect(described_class.for(react_js)).to eq 1

        create_ruby_dependency("react", dependent_id: 2)
        create_npm_dependency("react", dependent_id: 2)
        create_npm_dependency("react", dependent_id: 3)
        create_npm_dependency("leftpad", dependent_id: 3)

        described_class.update

        expect(described_class.count).to eq 3
        expect(described_class.for(react_ruby)).to eq 2
        expect(described_class.for(react_js)).to eq 3
      end
    end

    def create_ruby_dependency(package_name, dependent_id:)
      find_or_create_package_by_id(dependent_id)

      AbstractPackageDependency.create!({
        dependent_id:   dependent_id,
        package_manager: :rubygems,
        package_name:    package_name,
      })
    end

    def create_npm_dependency(package_name, dependent_id:)
      find_or_create_package_by_id(dependent_id)

      AbstractPackageDependency.create!({
        dependent_id:   dependent_id,
        package_manager: :npm,
        package_name:    package_name,
      })
    end

    def find_or_create_package_by_id(id)
      package = Package.find_or_initialize_by(id: id)
      return package if package.persisted?

      package.name = id.to_s
      package.save
      package
    end
  end
end
