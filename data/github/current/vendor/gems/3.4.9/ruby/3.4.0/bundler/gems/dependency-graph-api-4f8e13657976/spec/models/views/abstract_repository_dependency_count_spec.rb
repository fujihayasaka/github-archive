require "rails_helper"

module Views
  describe AbstractRepositoryDependencyCount do
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
        create_ruby_dependency("react", repository_id: 1)
        create_ruby_dependency("react", repository_id: 2)

        create_npm_dependency("react", repository_id: 1)
        create_npm_dependency("react", repository_id: 2)
        create_npm_dependency("react", repository_id: 3)

        described_class.rebuild

        expect(described_class.count).to eq 2
        expect(described_class.for(react_ruby)).to eq 2
        expect(described_class.for(react_js)).to eq 3
      end
    end

    describe ".run" do
      it "incrementally builds counts" do
        expect(described_class.count).to eq 0
        expect(described_class.for(react_ruby)).to eq 0
        expect(described_class.for(react_js)).to eq 0

        create_ruby_dependency("react", repository_id: 1)
        create_npm_dependency("react", repository_id: 1)

        described_class.update

        expect(described_class.count).to eq 2
        expect(described_class.for(react_ruby)).to eq 1
        expect(described_class.for(react_js)).to eq 1

        create_ruby_dependency("react", repository_id: 2)
        create_npm_dependency("react", repository_id: 2)
        create_npm_dependency("react", repository_id: 3)
        create_npm_dependency("leftpad", repository_id: 3)

        described_class.update

        expect(described_class.count).to eq 3
        expect(described_class.for(react_ruby)).to eq 2
        expect(described_class.for(react_js)).to eq 3
      end

      it "only counts public repos" do
        create_ruby_dependency("react", repository_id: 1)
        create_ruby_dependency("react", repository_id: 2, private: true)
        described_class.update

        expect(described_class.for(react_ruby)).to eq 1
      end
    end

    def find_or_create_repo_by_id(repository_id)
      Repository.find_or_create_by(id: repository_id, github_repository_id: repository_id)
    end

    def create_ruby_dependency(package_name, repository_id:, private: false)
      repo = find_or_create_repo_by_id(repository_id)
      repo.update(public: false) if private

      AbstractRepositoryDependency.create!({
        repository_id:   repository_id,
        package_manager: :rubygems,
        package_name:    package_name,
      })
    end

    def create_npm_dependency(package_name, repository_id:, private: false)
      repo = find_or_create_repo_by_id(repository_id)
      repo.update_attributes(public: false) if private

      AbstractRepositoryDependency.create!({
        repository_id:   repository_id,
        package_manager: :npm,
        package_name:    package_name,
      })
    end
  end
end
